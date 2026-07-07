#!/usr/bin/env bash
#
# shared helpers for the worktree pool
# source this from the `wt-*` commands rather than running it directly
#
# the pool keeps a set of reusable git worktrees so that expensive build trees (for example WebKit's `WebKitBuild/`) survive across sessions instead of being rebuilt from scratch
# each session owns a worktree through a lockfile that records its session identity (see `session_id`), so the pool behaves the same for a human at a terminal and for any coding agent

set -euo pipefail
shopt -s nullglob

POOL_ROOT="${WT_POOL_ROOT:-$HOME/Developer/worktrees}"
POOL_META="$POOL_ROOT/.pool"
LOCK_DIR="$POOL_META/locks"
# shellcheck disable=SC2034  # used by the sourcing commands
BUILD_LOCK="$POOL_META/build.lock"

# a worktree whose heartbeat is older than this many hours is treated as abandoned and may be reclaimed by another session
STALE_HOURS="${WT_STALE_HOURS:-18}"

# variable names, highest priority first, whose value identifies the current session
# the first one that is set wins, so `WT_SESSION_ID` or an agent's own variable takes precedence
# add your tool's variable here or set `WT_SESSION_ID`
WT_SESSION_ENV="${WT_SESSION_ENV:-WT_SESSION_ID COPILOT_AGENT_SESSION_ID TERM_SESSION_ID}"

mkdir -p "$LOCK_DIR"

now() { date +%s; }

log() { printf '[wt] %s\n' "$*" >&2; }

die() {
	printf '[wt] error: %s\n' "$*" >&2
	exit 1
}

short() { printf '%.8s' "$1"; }

# session_id prints a stable identity for the current session
# it checks the variables listed in `WT_SESSION_ENV`, then the controlling terminal, then the parent process, so it yields a usable value for humans and agents alike
# set `WT_SESSION_ID` to pin it explicitly
session_id() {
	local name val tty
	# shellcheck disable=SC2086  # WT_SESSION_ENV is a space separated name list
	for name in $WT_SESSION_ENV; do
		val="${!name:-}"
		if [ -n "$val" ]; then
			printf '%s' "$val" | tr -d '\r\n'
			return
		fi
	done
	tty="$(ps -o tty= -p "$$" 2>/dev/null | tr -d '[:space:]')"
	case "$tty" in
		''|'?'|'??')
			printf 'proc-%s-%s' "$(id -un)" "$PPID"
			;;
		*)
			printf 'tty-%s-%s' "$(id -un)" "$(printf '%s' "$tty" | tr -c 'A-Za-z0-9' '-')"
			;;
	esac
}

SESSION_ID="$(session_id)"

# repo_key <path> prints a filesystem safe key derived from the repo basename
repo_key() {
	local name
	name="$(basename "$1")"
	printf '%s' "$name" | tr -c 'A-Za-z0-9_.-' '_'
}

# resolve_repo [path] prints the absolute path of the main worktree that contains `path` (default: the current directory)
# resolving to the main worktree keeps the pool key stable whether a command runs from the checkout itself or from one of its linked worktrees
# shellcheck disable=SC2120  # the path argument is intentionally optional
resolve_repo() {
	local start="${1:-$PWD}" main
	main="$(git -C "$start" worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')" || true
	[ -n "$main" ] || die "not inside a git repository (pass --repo PATH)"
	printf '%s\n' "$main"
}

# repo_root_of <path> prints the main worktree path for the repo that contains <path>,
# or nothing when <path> is not inside a git repository
# unlike resolve_repo it never dies, so callers can use it only to compare two repos
repo_root_of() {
	local start="$1" main
	main="$(git -C "$start" worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')" || true
	[ -n "$main" ] || return 0
	printf '%s\n' "$main"
}

# default_base <repo> prints the repo's default branch that exists locally, trying `origin/HEAD`, then `main`, then `master`, then the current HEAD
default_base() {
	local repo="$1" origin cand
	origin="$(git -C "$repo" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)" || origin=""
	for cand in "${origin#origin/}" main master; do
		[ -n "$cand" ] || continue
		if git -C "$repo" rev-parse --verify --quiet "refs/heads/$cand" >/dev/null 2>&1; then
			printf '%s\n' "$cand"
			return 0
		fi
	done
	git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null || printf 'HEAD\n'
}

# read_field <lockfile> <key> prints the value, or nothing when it is absent
read_field() {
	local file="$1" key="$2"
	[ -f "$file" ] || return 0
	sed -n "s/^${key}=//p" "$file" | head -1
}

# lock_is_stale <lockfile> succeeds when the heartbeat is present and older than STALE_HOURS
# a lock without a numeric heartbeat is treated as fresh because it is being written right now
lock_is_stale() {
	local file="$1" hb limit
	hb="$(read_field "$file" heartbeat)"
	case "$hb" in
		''|*[!0-9]*) return 1 ;;
	esac
	limit=$(( STALE_HOURS * 3600 ))
	[ $(( $(now) - hb )) -ge "$limit" ]
}

# refresh_heartbeat <lockfile> rewrites the heartbeat to now, in place
# the temp file lives beside the lock so the replacing `mv` stays on one filesystem and is therefore atomic
refresh_heartbeat() {
	local file="$1" tmp
	[ -f "$file" ] || return 0
	tmp="$(mktemp "${file}.XXXXXX")" || return 0
	if {
		grep -v '^heartbeat=' "$file" || true
		printf 'heartbeat=%s\n' "$(now)"
	} > "$tmp" && mv -f "$tmp" "$file"; then
		return 0
	fi
	rm -f "$tmp"
	return 0
}

# acquire <lockfile> <repo> <worktree> <branch> <note>
# writes the full lock body to a temp file and hardlinks it into place
# `ln` fails if the target exists, which makes the claim atomic and guarantees the lock is never observed without its contents
# it succeeds only for the winner
acquire() {
	local file="$1" repo="$2" wt="$3" branch="$4" note="$5" tmp ts
	ts="$(now)"
	note="$(printf '%s' "$note" | tr -d '\r\n')"
	tmp="$(mktemp "${file}.XXXXXX")" || return 1
	cat > "$tmp" <<EOF
session=$SESSION_ID
repo=$repo
worktree=$wt
branch=$branch
claimed_at=$ts
heartbeat=$ts
note=$note
EOF
	if ln "$tmp" "$file" 2>/dev/null; then
		rm -f "$tmp"
		return 0
	fi
	rm -f "$tmp"
	return 1
}

# with_lock <mutex> <cmd...> runs cmd while holding a short lived mutex, so that
# racing sessions serialize their lock mutations
# a mutex left behind by a crashed process is recovered after a few minutes
# it returns 75 (and never runs cmd) if the mutex cannot be acquired, otherwise it returns cmd's own status
WT_LOCK_BUSY=75
with_lock() {
	local mx="$1" held=0 tries=0 rc=0 max="${WT_LOCK_TRIES:-200}"
	shift
	while [ "$tries" -lt "$max" ]; do
		if mkdir "$mx" 2>/dev/null; then
			held=1
			break
		fi
		# find prints the path only when the mtime matches, so test its output (its exit status is 0 either way)
		# the threshold is generous so a legitimately slow critical section (a large `git reset`) is never mistaken for a crashed holder
		if [ -n "$(find "$mx" -maxdepth 0 -mmin +5 2>/dev/null)" ]; then
			# steal the stale mutex by renaming it first, so only the one winner deletes it and two waiters cannot both recover
			mv "$mx" "$mx.reap.$$" 2>/dev/null && rm -rf "$mx.reap.$$" 2>/dev/null
			continue
		fi
		tries=$(( tries + 1 ))
		sleep 0.05
	done
	[ "$held" -eq 1 ] || return "$WT_LOCK_BUSY"
	"$@" || rc=$?
	rmdir "$mx" 2>/dev/null || rm -rf "$mx" 2>/dev/null || true
	return "$rc"
}

# claim_slot <lockfile> <repo> <worktree> <branch> <note> claims a free or stale
# slot, re-checking staleness so a concurrent reclaim cannot be clobbered
# always run this through `with_lock`
# shellcheck disable=SC2317  # invoked indirectly through with_lock
claim_slot() {
	local lock="$1"
	shift
	if [ -e "$lock" ]; then
		lock_is_stale "$lock" || return 1
		rm -f "$lock"
	fi
	acquire "$lock" "$@"
}

# worktree_is_dirty <worktree> succeeds when it has uncommitted changes to tracked
# files or untracked files that are not ignored
worktree_is_dirty() {
	[ -n "$(git -C "$1" status --porcelain 2>/dev/null)" ]
}

# disambiguate_worktrees <what> <match...> prints the single pooled worktree to use
# when one or more matched a selector, for example the same branch checked out in
# several repos' worktrees
# with more than one match it infers the intended one from the current directory:
# first a match the current directory sits inside, then the one match belonging to the
# same repo as the current directory, and only when the choice is still ambiguous does
# it die
# the caller handles the zero match case, whose wording differs per caller
disambiguate_worktrees() {
	local what="$1" wt here_repo narrowed="" ncount=0 names=""
	shift
	if [ "$#" -eq 1 ]; then
		printf '%s\n' "$1"
		return 0
	fi
	# the current directory is inside one of the matches
	for wt in "$@"; do
		case "$PWD/" in
			"$wt"/*)
				printf '%s\n' "$wt"
				return 0
				;;
		esac
	done
	# exactly one match belongs to the same repo as the current directory
	here_repo="$(repo_root_of "$PWD")"
	if [ -n "$here_repo" ]; then
		for wt in "$@"; do
			if [ "$(repo_root_of "$wt")" = "$here_repo" ]; then
				narrowed="$wt"
				ncount=$(( ncount + 1 ))
			fi
		done
		if [ "$ncount" -eq 1 ]; then
			printf '%s\n' "$narrowed"
			return 0
		fi
	fi
	for wt in "$@"; do
		names="${names:+$names, }$(basename "$wt")"
	done
	die "$what is checked out in multiple worktrees ($names); use --worktree to choose"
}

# find_pool_worktree_by_branch <ref> prints the pooled worktree that currently has
# <ref> checked out
# it dies when none match, and when several match it infers one from the current
# directory (see disambiguate_worktrees)
find_pool_worktree_by_branch() {
	local ref="$1" wt cur
	local matches=()
	for wt in "$POOL_ROOT"/*-*; do
		[ -d "$wt" ] || continue
		case "${wt##*-}" in
			''|*[!0-9]*) continue ;;
		esac
		cur="$(git -C "$wt" branch --show-current 2>/dev/null || true)"
		if [ "$cur" = "$ref" ]; then
			matches+=("$wt")
		fi
	done
	if [ "${#matches[@]}" -eq 0 ]; then
		die "no pooled worktree has branch '$ref' checked out"
	fi
	disambiguate_worktrees "branch '$ref'" "${matches[@]}"
}

# normalize_pool_worktree <name-or-path> prints the absolute path of a pooled
# worktree given either its bare name (like myrepo-1) or a path to it
# it dies when the value is not an existing pooled worktree
normalize_pool_worktree() {
	local val="$1" target
	case "$val" in
		*/*)
			[ -d "$val" ] || die "worktree path not found: $val"
			target="$(cd "$val" && pwd)"
			;;
		*)
			target="$POOL_ROOT/$val"
			;;
	esac
	case "$(basename "$target")" in
		*-*) ;;
		*) die "not a pooled worktree: $val" ;;
	esac
	[ -d "$target" ] || die "worktree not found: $(basename "$target")"
	printf '%s\n' "$target"
}

# resolve_target <want_worktree> <want_branch> prints the one pooled worktree
# selected by --worktree and/or --branch, and when both are given they must agree
# it returns 1 when neither selector is set, and dies when a selector matches nothing
resolve_target() {
	local want_wt="$1" want_branch="$2" target cur
	if [ -n "$want_wt" ]; then
		target="$(normalize_pool_worktree "$want_wt")" || return 1
		if [ -n "$want_branch" ]; then
			cur="$(git -C "$target" branch --show-current 2>/dev/null || true)"
			if [ "$cur" != "$want_branch" ]; then
				die "$(basename "$target") is on '${cur:-<detached>}', not branch '$want_branch'"
			fi
		fi
	elif [ -n "$want_branch" ]; then
		target="$(find_pool_worktree_by_branch "$want_branch")" || return 1
	else
		return 1
	fi
	printf '%s\n' "$target"
}

# is_pool_worktree_token <token> succeeds when <token> names or points at an existing
# pooled worktree (a bare name like myrepo-1, or a path to one)
is_pool_worktree_token() {
	local val="$1" target
	case "$val" in
		*/*)
			[ -d "$val" ] || return 1
			target="$(cd "$val" && pwd)" || return 1
			;;
		*)
			target="$POOL_ROOT/$val"
			;;
	esac
	case "$(basename "$target")" in
		*-*) ;;
		*) return 1 ;;
	esac
	[ -d "$target" ]
}

# in_pool_worktree prints the pooled worktree that contains the current directory,
# or nothing when the current directory is not inside a genuine pooled worktree
# it confirms membership (a `<repo-key>-<N>` linked worktree of its own repo) so a task
# named worktree such as `wk-262834`, or an unrelated checkout that merely lives under
# the pool root, is never mistaken for one
# unlike here_pool_worktree it never dies, so a command can use it to default its target
# to the worktree you are standing in
in_pool_worktree() {
	local rest first cand idx main
	case "$PWD/" in
		"$POOL_ROOT"/*) ;;
		*) return 0 ;;
	esac
	rest="${PWD#"$POOL_ROOT"/}"
	first="${rest%%/*}"
	# a pooled worktree is named `<repo-key>-<N>` with a numeric index
	case "$first" in
		*-*) ;;
		*) return 0 ;;
	esac
	idx="${first##*-}"
	case "$idx" in
		''|*[!0-9]*) return 0 ;;
	esac
	cand="$POOL_ROOT/$first"
	[ -d "$cand" ] || return 0
	# and its name matches the key of the repo it is a linked worktree of, which excludes
	# a task named worktree or any other checkout that happens to sit under the pool root
	main="$(repo_root_of "$cand")"
	[ -n "$main" ] || return 0
	[ "$first" = "$(repo_key "$main")-$idx" ] || return 0
	printf '%s\n' "$cand"
	return 0
}

# here_pool_worktree prints the pooled worktree that contains the current directory,
# so `.` targets the worktree you are standing in, even from a subdirectory
# it dies when the current directory is not inside a pooled worktree
here_pool_worktree() {
	local wt
	wt="$(in_pool_worktree)"
	if [ -z "$wt" ]; then
		die "not inside a pooled worktree (cwd: $PWD)"
	fi
	printf '%s\n' "$wt"
}

# resolve_target_token <token> prints the pooled worktree identified by a bare
# positional <token>, auto-detected as a worktree name/path (preferred) or, failing
# that, a branch checked out in a pooled worktree
resolve_target_token() {
	local token="$1" wt cur
	local matches=()
	if [ "$token" = "." ]; then
		here_pool_worktree
		return
	fi
	if is_pool_worktree_token "$token"; then
		normalize_pool_worktree "$token"
		return
	fi
	for wt in "$POOL_ROOT"/*-*; do
		[ -d "$wt" ] || continue
		case "${wt##*-}" in
			''|*[!0-9]*) continue ;;
		esac
		cur="$(git -C "$wt" branch --show-current 2>/dev/null || true)"
		if [ "$cur" = "$token" ]; then
			matches+=("$wt")
		fi
	done
	if [ "${#matches[@]}" -eq 0 ]; then
		die "'$token' is not a pooled worktree or a branch checked out in one"
	fi
	disambiguate_worktrees "branch '$token'" "${matches[@]}"
}

# select_target <positional> <want_wt> <want_branch> prints the chosen pooled worktree
# the positional is auto-detected (worktree or branch) and is mutually exclusive with
# --worktree/--branch, and it returns 1 when no selector was given
select_target() {
	local pos="$1" want_wt="$2" want_branch="$3"
	if [ -n "$pos" ]; then
		if [ -n "$want_wt" ] || [ -n "$want_branch" ]; then
			die "give a positional target or --branch/--worktree, not both"
		fi
		resolve_target_token "$pos"
	else
		resolve_target "$want_wt" "$want_branch"
	fi
}

# human_age <epoch> prints a compact age such as `3m`, `2h`, or `1d`
human_age() {
	local then="$1" diff
	case "$then" in
		''|*[!0-9]*) printf '?'; return ;;
	esac
	diff=$(( $(now) - then ))
	if [ "$diff" -lt 3600 ]; then
		printf '%dm' $(( diff / 60 ))
	elif [ "$diff" -lt 86400 ]; then
		printf '%dh' $(( diff / 3600 ))
	else
		printf '%dd' $(( diff / 86400 ))
	fi
}
