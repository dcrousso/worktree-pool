#!/usr/bin/env bash
# wt-path resolves a worktree path with no side effects
# shellcheck disable=SC2016,SC2034
# shellcheck source=harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/harness.sh"

repo="$(new_repo)"

echo "== path by owned worktree, name, and branch =="
w="$(COPILOT_AGENT_SESSION_ID=sP "$BIN/wt-claim" --repo "$repo" 2>/dev/null)"
lock="$LOCKS/$(basename "$w").lock"
before="$(cat "$lock")"
check '[ "$(COPILOT_AGENT_SESSION_ID=sP "$BIN/wt-path" --repo "$repo")" = "$w" ]' 'path with no target prints the worktree this session owns'
check '[ "$("$BIN/wt-path" "$(basename "$w")")" = "$w" ]' 'path <worktree-name> prints its path'
git -C "$w" checkout -q -b path-branch
check '[ "$("$BIN/wt-path" path-branch)" = "$w" ]' 'path <branch> prints the worktree on it'
check '[ "$("$BIN/wt-path" --branch path-branch)" = "$w" ]' 'path --branch prints the worktree'

echo "== path has no side effects =="
check '[ "$(cat "$lock")" = "$before" ]' 'path does not modify the lock'

echo "== errors =="
rc=0
"$BIN/wt-path" no-such-thing >/dev/null 2>&1 || rc=$?
check '[ "$rc" -ne 0 ]' 'path errors on an unknown token'
rc=0
COPILOT_AGENT_SESSION_ID=sNobody "$BIN/wt-path" --repo "$repo" >/dev/null 2>&1 || rc=$?
check '[ "$rc" -ne 0 ]' 'path with no target errors when the session owns nothing'

echo "== the . target is the worktree you are in =="
check '[ "$(cd "$w" && "$BIN/wt-path" .)" = "$w" ]' 'path . resolves the worktree you are in'
mkdir -p "$w/sub/dir"
check '[ "$(cd "$w/sub/dir" && "$BIN/wt-path" .)" = "$w" ]' 'path . works from a subdirectory'
rc=0
( cd "$ROOT" && "$BIN/wt-path" . ) >/dev/null 2>&1 || rc=$?
check '[ "$rc" -ne 0 ]' 'path . errors outside any pooled worktree'

echo "== no target from inside a worktree resolves that worktree =="
wp2="$(COPILOT_AGENT_SESSION_ID=sPw "$BIN/wt-claim" --repo "$repo" 2>/dev/null)"
mkdir -p "$wp2/nested"
check '[ "$(cd "$wp2" && COPILOT_AGENT_SESSION_ID=sStranger "$BIN/wt-path")" = "$wp2" ]' 'bare path from inside a worktree prints it, even for another session'
check '[ "$(cd "$wp2/nested" && COPILOT_AGENT_SESSION_ID=sStranger "$BIN/wt-path")" = "$wp2" ]' 'bare path from a subdirectory prints the worktree root'

echo "== a task-named worktree under the pool root is not inferred =="
git -C "$repo" worktree add -q --detach "$WT_POOL_ROOT/wk-262834" main >/dev/null 2>&1
rc=0
( cd "$WT_POOL_ROOT/wk-262834" && COPILOT_AGENT_SESSION_ID=sNoOwn "$BIN/wt-path" ) >/dev/null 2>&1 || rc=$?
check '[ "$rc" -ne 0 ]' 'bare path does not mistake a task-named worktree for a pooled one'

report
