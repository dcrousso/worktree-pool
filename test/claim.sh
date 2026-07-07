#!/usr/bin/env bash
# claiming and reclaiming worktrees
# shellcheck disable=SC2016,SC2034
# shellcheck source=harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/harness.sh"

repo="$(new_repo)"
claim() { COPILOT_AGENT_SESSION_ID="$1" "$BIN/wt-claim" --repo "$repo" --note "$2" 2>/dev/null; }

echo "== create and reuse =="
w1="$(claim sA 'task one')"
check '[ -d "$w1" ]' 'claim creates a worktree'
check '[ "$(basename "$w1")" = myrepo-1 ]' 'the worktree has a clean name'
check '[ "$(claim sA again)" = "$w1" ]' 're-entrant claim reuses the same worktree'
w2="$(claim sB 'task two')"
check '[ "$w2" != "$w1" ]' 'a second session gets a different worktree'
check '[ "$(basename "$w2")" = myrepo-2 ]' 'the second worktree is pool-2'

echo "== build cache survives release and reclaim =="
mkdir -p "$w1/out"
printf 'cached\n' > "$w1/out/artifact"
COPILOT_AGENT_SESSION_ID=sA "$BIN/wt-release" --repo "$repo" >/dev/null 2>&1
check '[ ! -e "$LOCKS/myrepo-1.lock" ]' 'release removes the lock'
check '[ -f "$w1/out/artifact" ]' 'ignored build output is kept'
w3="$(claim sC reuse)"
check '[ "$w3" = "$w1" ]' 'the freed worktree is reclaimed'
check '[ -f "$w3/out/artifact" ]' 'the build cache is reused'

echo "== stale reclaim =="
ws="$(claim sD stale)"
lock="$LOCKS/$(basename "$ws").lock"
sed "s/^heartbeat=.*/heartbeat=$(( $(date +%s) - 19 * 3600 ))/" "$lock" > "$lock.tmp" && mv "$lock.tmp" "$lock"
check '[ "$(claim sE reclaimer)" = "$ws" ]' 'another session reclaims a stale worktree'

echo "== dangling lock =="
wd="$(claim sF dangling)"
rm -rf "$wd"
check '[ -d "$(claim sF again)" ]' 're-claim recovers a deleted worktree dir'
check '[ -z "$(git -C "$repo" worktree prune --expire now --dry-run 2>/dev/null)" ]' 'no dangling git worktree metadata remains after a claim'

echo "== a dirty stale worktree is never reset =="
wdirty="$(claim sG dirty)"
printf 'precious uncommitted work\n' > "$wdirty/f.txt"
lockg="$LOCKS/$(basename "$wdirty").lock"
sed "s/^heartbeat=.*/heartbeat=$(( $(date +%s) - 19 * 3600 ))/" "$lockg" > "$lockg.t" && mv "$lockg.t" "$lockg"
wnext="$(claim sH reclaimer)"
check '[ "$wnext" != "$wdirty" ]' 'a claimant skips a dirty stale worktree'
check '[ "$(cat "$wdirty/f.txt")" = "precious uncommitted work" ]' 'the uncommitted work is preserved'

echo "== claim --branch checks out (creating) the branch =="
wcb="$(COPILOT_AGENT_SESSION_ID=sBranch "$BIN/wt-claim" --repo "$repo" --branch feature-y 2>/dev/null)"
check '[ "$(git -C "$wcb" branch --show-current)" = feature-y ]' 'claim --branch creates and checks out a new branch'
check 'git -C "$repo" rev-parse --verify --quiet feature-y >/dev/null' 'the new branch exists in the repo'
wce="$(COPILOT_AGENT_SESSION_ID=sBranch2 "$BIN/wt-claim" --repo "$repo" --branch dev 2>/dev/null)"
check '[ "$(git -C "$wce" branch --show-current)" = dev ]' 'claim --branch checks out a pre-existing branch'
wcp="$(COPILOT_AGENT_SESSION_ID=sClaimPos "$BIN/wt-claim" --repo "$repo" pos-feature 2>/dev/null)"
check '[ "$(git -C "$wcp" branch --show-current)" = pos-feature ]' 'claim REF (positional) checks out the branch'

echo "== claim --branch names the worktree already holding the branch =="
wshared="$(COPILOT_AGENT_SESSION_ID=sShare1 "$BIN/wt-claim" --repo "$repo" 2>/dev/null)"
git -C "$wshared" checkout -q -b shared-branch
err="$(COPILOT_AGENT_SESSION_ID=sShare2 "$BIN/wt-claim" --repo "$repo" --branch shared-branch 2>&1)"
rc=$?
check '[ "$rc" -ne 0 ]' 'claim --branch fails when the branch is checked out elsewhere'
check 'printf "%s" "$err" | grep -q "$(basename "$wshared")"' 'the error names the worktree that holds the branch'

report
