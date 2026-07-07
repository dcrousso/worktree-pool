#!/usr/bin/env bash
# releasing worktrees back to the pool
# shellcheck disable=SC2016,SC2034
# shellcheck source=harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/harness.sh"

repo="$(new_repo)"

echo "== release from inside the worktree =="
w="$(COPILOT_AGENT_SESSION_ID=sIn "$BIN/wt-claim" --repo "$repo" 2>/dev/null)"
out="$(cd "$w" && COPILOT_AGENT_SESSION_ID=sIn "$BIN/wt-release" 2>&1)"
check 'printf "%s" "$out" | grep -q "released myrepo-1"' 'wt-release works from inside a pooled worktree'
check '[ ! -e "$LOCKS/myrepo-1.lock" ]' 'the lock is removed'

echo "== release --all spans repos =="
repo2="$(new_repo otherrepo)"
COPILOT_AGENT_SESSION_ID=sAll "$BIN/wt-claim" --repo "$repo"  >/dev/null 2>&1
COPILOT_AGENT_SESSION_ID=sAll "$BIN/wt-claim" --repo "$repo2" >/dev/null 2>&1
before="$(grep -l '^session=sAll$' "$LOCKS"/*.lock 2>/dev/null | wc -l | tr -d ' ')"
COPILOT_AGENT_SESSION_ID=sAll "$BIN/wt-release" --all >/dev/null 2>&1
after="$(grep -l '^session=sAll$' "$LOCKS"/*.lock 2>/dev/null | wc -l | tr -d ' ')"
check '[ "$before" = 2 ]' 'the session owns a worktree in each repo'
check '[ "$after" = 0 ]' 'release --all frees them all'

echo "== a dirty worktree is protected =="
wd="$(COPILOT_AGENT_SESSION_ID=sDirty "$BIN/wt-claim" --repo "$repo" 2>/dev/null)"
lockd="$LOCKS/$(basename "$wd").lock"
printf 'work in progress\n' > "$wd/f.txt"
COPILOT_AGENT_SESSION_ID=sDirty "$BIN/wt-release" --repo "$repo" >/dev/null 2>&1
check '[ -e "$lockd" ]' 'release keeps a worktree with uncommitted changes'
check '[ "$(cat "$wd/f.txt")" = "work in progress" ]' 'the uncommitted change is preserved'
COPILOT_AGENT_SESSION_ID=sDirty "$BIN/wt-release" --repo "$repo" --force >/dev/null 2>&1
check '[ ! -e "$lockd" ]' 'release --force frees a dirty worktree'

echo "== release reports when a worktree is busy =="
wb="$(COPILOT_AGENT_SESSION_ID=sBusy "$BIN/wt-claim" --repo "$repo" 2>/dev/null)"
mkdir -p "$LOCKS/$(basename "$wb").lock.mx"   # hold the mutex so release cannot acquire it
rc=0
WT_LOCK_TRIES=2 COPILOT_AGENT_SESSION_ID=sBusy "$BIN/wt-release" --repo "$repo" > "$ROOT/busy.txt" 2>&1 || rc=$?
check '[ "$rc" -ne 0 ]' 'release exits nonzero when it cannot acquire the lock'
check 'grep -q busy "$ROOT/busy.txt"' 'release reports the worktree as busy'
check '[ -e "$LOCKS/$(basename "$wb").lock" ]' 'the lock is left intact when busy'
rmdir "$LOCKS/$(basename "$wb").lock.mx" 2>/dev/null || true

echo "== release --worktree reclaims another session's worktree =="
wo="$(COPILOT_AGENT_SESSION_ID=sGone "$BIN/wt-claim" --repo "$repo" 2>/dev/null)"
locko="$LOCKS/$(basename "$wo").lock"
COPILOT_AGENT_SESSION_ID=sOther "$BIN/wt-release" --worktree "$(basename "$wo")" > "$ROOT/wt.txt" 2>&1
check '[ ! -e "$locko" ]' 'release --worktree frees a worktree owned by another session'
check 'grep -q "released $(basename "$wo")" "$ROOT/wt.txt"' 'release --worktree reports the freed worktree'

echo "== release --branch reclaims by checked-out branch, keeping the branch ref =="
wbf="$(COPILOT_AGENT_SESSION_ID=sBr "$BIN/wt-claim" --repo "$repo" 2>/dev/null)"
git -C "$wbf" checkout -q -b feature-x
lockbf="$LOCKS/$(basename "$wbf").lock"
COPILOT_AGENT_SESSION_ID=sElse "$BIN/wt-release" --branch feature-x >/dev/null 2>&1
check '[ ! -e "$lockbf" ]' 'release --branch frees the worktree on that branch'
check '[ "$(git -C "$wbf" rev-parse --abbrev-ref HEAD)" = HEAD ]' 'the worktree is detached after release'
check 'git -C "$repo" rev-parse --verify --quiet feature-x >/dev/null' 'the released branch ref is kept'

echo "== --branch and --worktree must point at the same worktree =="
wm="$(COPILOT_AGENT_SESSION_ID=sMix "$BIN/wt-claim" --repo "$repo" 2>/dev/null)"
git -C "$wm" checkout -q -b real-branch
lockm="$LOCKS/$(basename "$wm").lock"
rc=0
"$BIN/wt-release" --worktree "$(basename "$wm")" --branch nope-branch >/dev/null 2>&1 || rc=$?
check '[ "$rc" -ne 0 ]' 'release errors when --branch does not match --worktree'
check '[ -e "$lockm" ]' 'the mismatched worktree is left intact'

echo "== an unknown branch or worktree is reported =="
rc=0
"$BIN/wt-release" --branch does-not-exist >/dev/null 2>&1 || rc=$?
check '[ "$rc" -ne 0 ]' 'release --branch errors when no worktree has that branch'
rc=0
"$BIN/wt-release" --worktree myrepo-999 >/dev/null 2>&1 || rc=$?
check '[ "$rc" -ne 0 ]' 'release --worktree errors on a nonexistent worktree'

echo "== an explicit dirty target is protected without --force =="
wdx="$(COPILOT_AGENT_SESSION_ID=sDx "$BIN/wt-claim" --repo "$repo" 2>/dev/null)"
printf 'wip\n' > "$wdx/f.txt"
lockdx="$LOCKS/$(basename "$wdx").lock"
"$BIN/wt-release" --worktree "$(basename "$wdx")" >/dev/null 2>&1
check '[ -e "$lockdx" ]' 'release --worktree keeps a dirty worktree without --force'
"$BIN/wt-release" --worktree "$(basename "$wdx")" --force >/dev/null 2>&1
check '[ ! -e "$lockdx" ]' 'release --worktree --force frees a dirty worktree'

echo "== positional target auto-detects a worktree name or a branch =="
wp="$(COPILOT_AGENT_SESSION_ID=sPosW "$BIN/wt-claim" --repo "$repo" 2>/dev/null)"
COPILOT_AGENT_SESSION_ID=sX "$BIN/wt-release" "$(basename "$wp")" >/dev/null 2>&1
check '[ ! -e "$LOCKS/$(basename "$wp").lock" ]' 'release <worktree-name> frees it without --worktree'
wpb="$(COPILOT_AGENT_SESSION_ID=sPosB "$BIN/wt-claim" --repo "$repo" 2>/dev/null)"
git -C "$wpb" checkout -q -b pos-branch
COPILOT_AGENT_SESSION_ID=sX "$BIN/wt-release" pos-branch >/dev/null 2>&1
check '[ ! -e "$LOCKS/$(basename "$wpb").lock" ]' 'release <branch-name> frees the worktree on it without --branch'

echo "== positional guards =="
rc=0
"$BIN/wt-release" some-token --branch other-token >/dev/null 2>&1 || rc=$?
check '[ "$rc" -ne 0 ]' 'release errors when a positional and --branch are both given'
rc=0
"$BIN/wt-release" not-a-worktree-or-branch >/dev/null 2>&1 || rc=$?
check '[ "$rc" -ne 0 ]' 'release errors on a token that is neither a worktree nor a branch'
rc=0
"$BIN/wt-release" --all some-token >/dev/null 2>&1 || rc=$?
check '[ "$rc" -ne 0 ]' 'release errors when --all is combined with a specific target'

echo "== --delete-branch drops the checked-out branch, not the base =="
wdb="$(COPILOT_AGENT_SESSION_ID=sDelBr "$BIN/wt-claim" --repo "$repo" 2>/dev/null)"
git -C "$wdb" checkout -q -b drop-me
COPILOT_AGENT_SESSION_ID=sX "$BIN/wt-release" drop-me --delete-branch >/dev/null 2>&1
check '[ ! -e "$LOCKS/$(basename "$wdb").lock" ]' 'release --delete-branch frees the worktree'
check '! git -C "$repo" rev-parse --verify --quiet drop-me >/dev/null' 'release --delete-branch deletes the checked-out branch'
check 'git -C "$repo" rev-parse --verify --quiet main >/dev/null' 'release --delete-branch keeps the base branch'

echo "== multiple positional targets in one call =="
m1="$(COPILOT_AGENT_SESSION_ID=sMulti1 "$BIN/wt-claim" --repo "$repo" 2>/dev/null)"
m2="$(COPILOT_AGENT_SESSION_ID=sMulti2 "$BIN/wt-claim" --repo "$repo" 2>/dev/null)"
git -C "$m2" checkout -q -b multi-branch
COPILOT_AGENT_SESSION_ID=sX "$BIN/wt-release" "$(basename "$m1")" multi-branch >/dev/null 2>&1
check '[ ! -e "$LOCKS/$(basename "$m1").lock" ]' 'release frees the first of several targets (by name)'
check '[ ! -e "$LOCKS/$(basename "$m2").lock" ]' 'release frees the second of several targets (by branch)'

echo "== a bare release from inside a worktree acts on that worktree, regardless of session =="
wself="$(COPILOT_AGENT_SESSION_ID=sOwner "$BIN/wt-claim" --repo "$repo" 2>/dev/null)"
git -C "$wself" checkout -q -b inside-branch
lockself="$LOCKS/$(basename "$wself").lock"
out="$(cd "$wself" && COPILOT_AGENT_SESSION_ID=sStranger "$BIN/wt-release" 2>&1)"
check 'printf "%s" "$out" | grep -q "released $(basename "$wself")"' 'bare release from inside frees the worktree even for another session'
check '[ ! -e "$lockself" ]' 'the lock is removed'
check '[ "$(git -C "$wself" rev-parse --abbrev-ref HEAD)" = HEAD ]' 'the worktree is detached after release'
check 'git -C "$repo" rev-parse --verify --quiet inside-branch >/dev/null' 'the checked-out branch ref is kept'

echo "== a bare release works from a subdirectory of the worktree =="
wsub="$(COPILOT_AGENT_SESSION_ID=sSub "$BIN/wt-claim" --repo "$repo" 2>/dev/null)"
locksub="$LOCKS/$(basename "$wsub").lock"
mkdir -p "$wsub/a/b"
( cd "$wsub/a/b" && COPILOT_AGENT_SESSION_ID=sStranger "$BIN/wt-release" >/dev/null 2>&1 )
check '[ ! -e "$locksub" ]' 'bare release from a subdirectory frees the worktree'

echo "== a bare release outside any worktree still releases this session's worktrees =="
wown="$(COPILOT_AGENT_SESSION_ID=sOutside "$BIN/wt-claim" --repo "$repo" 2>/dev/null)"
lockown="$LOCKS/$(basename "$wown").lock"
( cd "$repo" && COPILOT_AGENT_SESSION_ID=sOutside "$BIN/wt-release" >/dev/null 2>&1 )
check '[ ! -e "$lockown" ]' 'bare release from the main checkout frees the session-owned worktree'

echo "== a bare release targets the worktree underfoot, not another one this session owns =="
wA="$(COPILOT_AGENT_SESSION_ID=sPrecA "$BIN/wt-claim" --repo "$repo" 2>/dev/null)"
wB="$(COPILOT_AGENT_SESSION_ID=sPrecB "$BIN/wt-claim" --repo "$repo" 2>/dev/null)"
( cd "$wB" && COPILOT_AGENT_SESSION_ID=sPrecA "$BIN/wt-release" >/dev/null 2>&1 )
check '[ ! -e "$LOCKS/$(basename "$wB").lock" ]' 'bare release frees the worktree you are standing in'
check '[ -e "$LOCKS/$(basename "$wA").lock" ]' 'it leaves the other worktree this session owns alone'

echo "== --repo from inside a worktree keeps the session-scoped behavior =="
wR="$(COPILOT_AGENT_SESSION_ID=sRepo "$BIN/wt-claim" --repo "$repo" 2>/dev/null)"
( cd "$wR" && COPILOT_AGENT_SESSION_ID=sStranger "$BIN/wt-release" --repo "$repo" >/dev/null 2>&1 )
check '[ -e "$LOCKS/$(basename "$wR").lock" ]' 'release --repo ignores the worktree underfoot when the session owns nothing'

echo "== a bare release never touches a task-named worktree under the pool root =="
git -C "$repo" worktree add -q -b task-branch "$WT_POOL_ROOT/wk-262834" main >/dev/null 2>&1
( cd "$WT_POOL_ROOT/wk-262834" && COPILOT_AGENT_SESSION_ID=sNoOwn "$BIN/wt-release" >/dev/null 2>&1 )
check '[ "$(git -C "$WT_POOL_ROOT/wk-262834" rev-parse --abbrev-ref HEAD)" = task-branch ]' 'a task-named worktree is not mistaken for a pooled one'
check '[ ! -e "$LOCKS/wk-262834.lock" ]' 'no lock is created for a task-named worktree'

report
