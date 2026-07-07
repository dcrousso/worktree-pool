#!/usr/bin/env bash
# shared setup and assertions for the pool tests
# each test file sources this, runs `check` assertions, then calls `report`
# the `check` helper evaluates its expression with `eval`, so single quoted expressions expand at runtime
# shellcheck disable=SC2016,SC2034
set -u

BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" && pwd)"
ROOT="$(mktemp -d)"
# shellcheck disable=SC2154  # rc is assigned inside the trap body
trap 'rc=$?; rm -rf "$ROOT"; exit $rc' EXIT

export WT_POOL_ROOT="$ROOT/pool"
export WT_STALE_HOURS=18
mkdir -p "$WT_POOL_ROOT"
LOCKS="$WT_POOL_ROOT/.pool/locks"

# tests set identity explicitly, so drop whatever the surrounding tool exported
unset COPILOT_AGENT_SESSION_ID WT_SESSION_ID TERM_SESSION_ID

pass=0
fail=0

ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$*"; }
no() { fail=$((fail + 1)); printf 'FAIL %s\n' "$*"; }
check() { if eval "$1"; then ok "$2"; else no "$2 :: [$1]"; fi; }

# lib <fn> [args...] sources wt-lib.sh in a subshell and runs one of its functions
lib() { /bin/bash -c 'source "$1"; shift; "$@"' _ "$BIN/wt-lib.sh" "$@"; }

# sid runs session_id from wt-lib.sh, inheriting the current environment
sid() { /bin/bash -c 'source "$1"; session_id' _ "$BIN/wt-lib.sh"; }

# new_repo [name] creates a throwaway git repo with a main and a dev branch, and prints its path
# shellcheck disable=SC2120  # the name argument is optional
new_repo() {
	local name="${1:-myrepo}" repo
	repo="$ROOT/$name"
	{
		git init -q -b main "$repo"
		git -C "$repo" config user.email t@t
		git -C "$repo" config user.name t
		printf 'hello\n' > "$repo/f.txt"
		printf 'out/\n*.o\n' > "$repo/.gitignore"
		git -C "$repo" add .
		git -C "$repo" commit -qm init
		git -C "$repo" branch dev
	} >/dev/null 2>&1
	printf '%s\n' "$repo"
}

report() {
	printf 'RESULT: %d passed, %d failed\n' "$pass" "$fail"
	[ "$fail" -eq 0 ]
}
