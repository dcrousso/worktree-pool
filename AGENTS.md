# using the worktree pool (for AI agents)

this teaches an AI coding agent how to drive the worktree pool

read `README.md` for the full design, this file is the short operational version

## identity first

the pool tracks who owns a worktree by a session id, so it must be stable for your whole session and unique across concurrent sessions

it is detected automatically for GitHub Copilot (`COPILOT_AGENT_SESSION_ID`) and for a terminal (`TERM_SESSION_ID`)

for any other agent, export it once at the start of the session:
```bash
export WT_SESSION_ID="<a stable id unique to this session>"
```

if you skip this and no terminal id is present, every `wt claim` may look like a new session and pile up worktrees

## the loop

```bash
BIN=~/Developer/worktrees/.pool/bin

# claim (or reuse) a worktree already on your task branch (created from the base if new); the path is printed on stdout
WT="$("$BIN/wt" claim --repo ~/Developer/WebKit --branch <you>/<task> --note 'what you are doing')"
cd "$WT"

# ...edit files...

# build through wt so heavy builds run one at a time across the machine
"$BIN/wt" build -- Tools/Scripts/build-webkit --release

# at the start of each later turn, re-claim to refresh the heartbeat (re-entrant)
"$BIN/wt" claim --repo ~/Developer/WebKit >/dev/null

# when the task is done, leave the branch for review and return the worktree
git switch --detach
"$BIN/wt" release --repo ~/Developer/WebKit
```

## rules

- always build through `wt build --`, never invoke the build directly, or builds will thrash each other
- claim again at the start of every turn, it reuses the same worktree and refreshes the heartbeat
- commit or push your branch before `wt release`, a worktree with uncommitted changes is kept unless you pass `--force`
- run from inside a worktree, a bare `wt release` (or `wt path`) acts on that worktree, so you need not name it, and it acts regardless of which session owns the lock
- to reclaim disk, `wt remove` deletes free or stale worktrees, but prefer `wt release` so the build cache survives
- to reclaim a worktree whose session has gone away, name it: `wt release <branch-or-name>` (and `wt remove <branch-or-name>`) act regardless of which session owns it
- check `wt status` before assuming a worktree is free, never touch one owned by another session
- `wt claim` writes the path to stdout and logs to stderr, so `cd "$("$BIN/wt" claim ...)"` is safe
- if a command needs a specific base, pass `--base <ref>`, otherwise the repo default branch is used
