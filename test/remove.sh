#!/usr/bin/env bash
# removing pooled worktrees to reclaim disk
# shellcheck disable=SC2016,SC2034
# shellcheck source=harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/harness.sh"

repo="$(new_repo)"
claim() { COPILOT_AGENT_SESSION_ID="$1" "$BIN/wt-claim" --repo "$repo" 2>/dev/null; }
remove() { COPILOT_AGENT_SESSION_ID=sRm "$BIN/wt-remove" --repo "$repo" "$@"; }

echo "== a free worktree is removed, a live one is kept =="
w1="$(claim s1)"
w2="$(claim s2)"
COPILOT_AGENT_SESSION_ID=s1 "$BIN/wt-release" --repo "$repo" >/dev/null 2>&1
remove >/dev/null 2>&1
check '[ ! -e "$w1" ]' 'a free worktree is deleted'
check '[ ! -e "$LOCKS/$(basename "$w1").lock" ]' 'its lock is gone'
check '[ -d "$w2" ]' 'a worktree held by a live session is kept'
check '! git -C "$repo" worktree list --porcelain | grep -q "/myrepo-1$"' 'git metadata dropped the removed worktree'

echo "== --force removes a live worktree =="
remove --force >/dev/null 2>&1
check '[ ! -e "$w2" ]' '--force removes a live worktree'

echo "== --dry-run removes nothing =="
w3="$(claim s3)"
COPILOT_AGENT_SESSION_ID=s3 "$BIN/wt-release" --repo "$repo" >/dev/null 2>&1
remove --dry-run > "$ROOT/rm.txt" 2>&1
check 'grep -q "would remove" "$ROOT/rm.txt"' '--dry-run reports what it would remove'
check '[ -d "$w3" ]' '--dry-run leaves the worktree in place'

echo "== the current directory is never removed =="
w4="$(claim s4)"
COPILOT_AGENT_SESSION_ID=s4 "$BIN/wt-release" --repo "$repo" >/dev/null 2>&1
( cd "$w4" && remove >/dev/null 2>&1 )
check '[ -d "$w4" ]' 'wt-remove keeps the worktree it is run from'

echo "== remove --worktree deletes a specific worktree regardless of owner =="
wr="$(claim sOwn)"
COPILOT_AGENT_SESSION_ID=sElse "$BIN/wt-remove" --worktree "$(basename "$wr")" --force >/dev/null 2>&1
check '[ ! -d "$wr" ]' 'remove --worktree --force deletes a live worktree owned by another session'

echo "== remove --branch deletes the worktree on that branch =="
wrb="$(claim sBr2)"
git -C "$wrb" checkout -q -b to-delete
COPILOT_AGENT_SESSION_ID=sElse "$BIN/wt-remove" --branch to-delete --force >/dev/null 2>&1
check '[ ! -d "$wrb" ]' 'remove --branch --force deletes the worktree on that branch'

echo "== remove --branch is guarded and reports unknown targets =="
wrc="$(claim sBr3)"
git -C "$wrc" checkout -q -b keep-me
COPILOT_AGENT_SESSION_ID=sElse "$BIN/wt-remove" --branch keep-me >/dev/null 2>&1
check '[ -d "$wrc" ]' 'remove --branch keeps a live worktree without --force'
rc=0
"$BIN/wt-remove" --branch no-such-branch >/dev/null 2>&1 || rc=$?
check '[ "$rc" -ne 0 ]' 'remove --branch errors when no worktree has that branch'

echo "== positional target auto-detects a worktree name or a branch =="
wpr="$(claim sPosRm)"
COPILOT_AGENT_SESSION_ID=sElse "$BIN/wt-remove" "$(basename "$wpr")" --force >/dev/null 2>&1
check '[ ! -d "$wpr" ]' 'remove <worktree-name> deletes it without --worktree'
wprb="$(claim sPosRmB)"
git -C "$wprb" checkout -q -b rm-pos
COPILOT_AGENT_SESSION_ID=sElse "$BIN/wt-remove" rm-pos --force >/dev/null 2>&1
check '[ ! -d "$wprb" ]' 'remove <branch-name> deletes the worktree on it without --branch'
rc=0
"$BIN/wt-remove" --all some-token >/dev/null 2>&1 || rc=$?
check '[ "$rc" -ne 0 ]' 'remove errors when --all is combined with a specific target'

echo "== multiple positional targets in one call =="
rm1="$(claim sMultiRm1)"
rm2="$(claim sMultiRm2)"
git -C "$rm2" checkout -q -b multi-rm
COPILOT_AGENT_SESSION_ID=sElse "$BIN/wt-remove" "$(basename "$rm1")" multi-rm --force >/dev/null 2>&1
check '[ ! -d "$rm1" ]' 'remove deletes the first of several targets (by name)'
check '[ ! -d "$rm2" ]' 'remove deletes the second of several targets (by branch)'

echo "== unrelated directories are never deleted =="
plain="$WT_POOL_ROOT/myrepo-77"
mkdir -p "$plain"
printf 'not a worktree\n' > "$plain/keepme"
backup="$WT_POOL_ROOT/myrepo-backup"
mkdir -p "$backup"
COPILOT_AGENT_SESSION_ID=sRm "$BIN/wt-remove" --all --force >/dev/null 2>&1
check '[ -f "$plain/keepme" ]' 'a plain directory that has no .git is left alone'
check '[ -d "$backup" ]' 'a non-numeric pool-like directory is ignored'

report
