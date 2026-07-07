# worktree pool

a pool of reusable git worktrees shared across sessions, so expensive build trees (especially WebKit's `WebKitBuild/`) are reused instead of rebuilt from scratch every time

each session owns a worktree through a lockfile that records its session identity

a released worktree is reset to a clean base but keeps its build output, so the next session that claims it only needs an incremental build

## commands

all commands live in `~/Developer/worktrees/.pool/bin`

the `wt` entry point dispatches to the rest, so `wt claim` runs `wt-claim` and so on

put the `bin` directory on your `PATH` for the nicest experience:

```bash
export PATH="$HOME/Developer/worktrees/.pool/bin:$PATH"
```

| command | purpose |
|---|---|
| `wt claim [--repo PATH] [--base REF] [--branch REF] [--note TEXT] [--refresh]` | claim (or create) a worktree and print its path (re-running reuses the same worktree and refreshes its heartbeat); `--branch REF`, or a bare `wt claim REF`, also checks out REF, creating it from the base if needed |
| `wt release [--repo PATH] [--base REF] [--all] [--force]` | return this session's worktree to the pool, reset to a clean base but keeping the build cache (a worktree with uncommitted changes is kept unless `--force`); run with no arguments from inside a pooled worktree, it releases that worktree instead (like `.`) |
| `wt release NAME\|REF... [--force] [--delete-branch]` (or `--worktree NAME` / `--branch REF`) | release one or more specific pooled worktrees, each named by its worktree name/path, its checked-out branch, or `.` for the one you are in (auto-detected), whichever session owns it, so you can reclaim a departed session's worktree by hand; `--delete-branch` also drops the branch ref |
| `wt build [NAME\|REF] -- <cmd...>` | run a build under a machine wide lock so only one heavy build runs at a time across all sessions; a leading worktree/branch/`.` (or `--worktree`/`--branch`) runs the command in that worktree instead of the current directory |
| `wt status [--disk] [--mine] [--porcelain] [--repo PATH]` | show pool state: worktrees, owners, the branch each has checked out, idle age, warm-build flag, and the global build lock; `>` marks the worktree you are in, `--mine` shows only yours, `--repo` scopes to one repo, `--disk` adds sizes, `--porcelain` emits tab-separated fields for scripting |
| `wt migrate [--dry-run]` | normalize any legacy worktree names to the current scheme (safe to run repeatedly) |
| `wt remove [--repo PATH] [--all] [--force] [--dry-run]` | delete free or stale pooled worktrees to reclaim disk (a live or dirty worktree is kept unless `--force`) |
| `wt remove NAME\|REF... [--force] [--dry-run]` (or `--worktree NAME` / `--branch REF`) | delete one or more specific pooled worktrees, each named by its worktree name/path, its checked-out branch, or `.` (auto-detected), whichever session owns it |
| `wt path [NAME\|REF]` (or `--worktree NAME` / `--branch REF`) | print a pooled worktree's path with no side effects, by name/branch/`.`, or (no argument) the worktree the current directory is in, else the one this session owns; handy as `cd "$(wt path <branch>)"` |
| `wt doctor [--fix]` | report inconsistencies (orphaned locks, leftover mutexes, dangling worktrees); `--fix` cleans up orphaned locks and mutexes and prunes git worktree metadata |

run `wt <command> --help` for the options of a command

run from inside a pooled worktree, a bare `wt release` or `wt path` (no argument) acts on that worktree, so you never have to name the one you are standing in

when a branch is checked out in worktrees for several repos, a bare `NAME|REF` or `--branch REF` resolves the ambiguity from the current directory: the worktree you are standing in, otherwise the one for the current repo

## shell integration

optional niceties once `bin` is on your `PATH`:

```bash
# tab-complete subcommands, flags, and live worktree/branch names
source ~/Developer/worktrees/.pool/bin/wt-completion.bash

# jump into a worktree by branch or name (a subprocess cannot cd the parent shell)
wtcd() { local p; p="$(wt path "$@")" && cd "$p"; }
```

then `wt release <TAB>` offers the pooled worktrees and their checked-out branches, and `wtcd pr-68663-slotted` drops you straight into that worktree

## example

```bash
WT="$(wt claim --repo ~/Developer/WebKit --note 'bug 262834')"
cd "$WT"
git switch -c dcrousso/my-task
# ... make edits now ...
wt build -- Tools/Scripts/build-webkit --release
wt build -- Tools/Scripts/run-webkit-tests --release --no-build inspector
# leave the branch for review and return the worktree:
git switch --detach
wt release --repo ~/Developer/WebKit
```

call `wt claim` again at the start of each turn during a long session

it is re-entrant, so it returns the same worktree and refreshes the heartbeat

## configuration

the pool reads a few environment variables:

- `WT_POOL_ROOT` sets the pool root (default `~/Developer/worktrees`)
- `WT_STALE_HOURS` sets the idle hours before a lock is reclaimable (default `18`)
- `WT_BUILD_DIRS` sets the paths that `wt status` treats as a warm build cache, colon separated and relative to a worktree
- `WT_SESSION_ID` is set from any tool that has its own per session id
- `WT_SESSION_ENV` is the ordered list of variable names to read the identity from (default `WT_SESSION_ID COPILOT_AGENT_SESSION_ID TERM_SESSION_ID`)

### session identity

a session is whatever the first set variable in `WT_SESSION_ENV` says it is (by default `WT_SESSION_ID`, then `COPILOT_AGENT_SESSION_ID`, then `TERM_SESSION_ID`)

when none is set, the pool falls back to the controlling terminal, and then to the parent process

so it works out of the box for a human at a terminal and for GitHub Copilot

for any other agent (claude, codex, cursor, aider, etc.), point the pool at that tool's own session value once:

```bash
export WT_SESSION_ID="<your tool's stable per session id>"
```

or add the tool's variable to the search list:

```bash
export WT_SESSION_ENV="WT_SESSION_ID MY_AGENT_SESSION_ID TERM_SESSION_ID"
```

## design

### ownership and locking

each worktree has one lockfile at `.pool/locks/<name>.lock`, kept outside the worktree so it never appears in `git status`

a claim is atomic

the full lock body is written to a temp file and hardlinked into place with `ln`, which fails if the target already exists, so two sessions can never both win and a lock is never seen without its contents

reclaiming a free or stale lock is serialized by a short lived mutex, so two racing sessions can never both take over the same worktree

### claim order

a claim first reuses a worktree this session already owns, then takes any free or stale worktree so its build cache is reused, and only creates a new worktree when every existing one is busy

the lock for a new index is acquired before `git worktree add`, so racing sessions cannot collide on the same index

### release instead of delete

releasing resets the worktree to a clean detached base with `git clean -fd`

there is no `-x`, so ignored build output such as `WebKitBuild/` stays in place

the lockfile is removed and the worktree remains for the next claimant

### stale reclaim

each turn refreshes the lock heartbeat

a lock idle for longer than `WT_STALE_HOURS` (default `18`) is treated as abandoned and may be reclaimed

new worktrees are preferred over reclaiming, so an idle but live session is left alone

### global build lock

`wt build` serializes builds machine wide through an `fcntl` lock, because `flock(1)` is not available on macOS

concurrent WebKit builds already saturate the CPU and share Xcode's compilation cache, so running several at once only thrashes CPU and IO

serializing keeps each one fast

### default branch

when `--base` is omitted, the base is detected from `origin/HEAD`, falling back to `main`, then `master`, then the current `HEAD`

## q/a

### why not ccache?

as of Xcode 26, content addressable compilation caching is built into LLVM and enabled by WebKit (`COMPILATION_CACHE_ENABLE_CACHING`)

that cache lives at `~/Library/Developer/Xcode/DerivedData/CompilationCache.noindex` (tens of GB) and is already shared across every worktree on the machine, which is why both incremental and fresh worktree builds get cache hits automatically

a separate ccache would be redundant, so it is intentionally omitted

## notes

- pooled worktrees are named `<repo>-<N>` and are keyed by the repo basename, so a WebKit worktree is never confused with a playwright one
- task named worktrees such as `wk-262834` are never touched by the pool
- the commands target macOS system `bash` (`3.2`) and `python3`, so they also run on Linux without changes
- `test/selftest.sh` runs the whole suite, and each file under `test/` (`claim.sh`, `release.sh`, `migrate.sh`, and so on) also runs on its own
- every test builds its own isolated pool against throwaway repos and never touches the real pool
