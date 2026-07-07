#!/usr/bin/env bash
# wt-status output
# shellcheck disable=SC2016,SC2034
# shellcheck source=harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/harness.sh"

repo="$(new_repo)"
wSt="$(COPILOT_AGENT_SESSION_ID=sSt "$BIN/wt-claim" --repo "$repo" 2>/dev/null)"
out="$(COPILOT_AGENT_SESSION_ID=sSt "$BIN/wt-status" 2>&1)"

echo "== status =="
check 'printf "%s" "$out" | grep -q myrepo-1' 'status lists the worktree'
check 'printf "%s" "$out" | grep -q "(me)"' 'status marks this session'
check 'printf "%s" "$out" | grep -q "Global build lock: free"' 'status shows the build lock is free'

echo "== status --disk =="
outd="$(COPILOT_AGENT_SESSION_ID=sSt "$BIN/wt-status" --disk 2>&1)"
check 'printf "%s" "$outd" | grep -q SIZE' 'status --disk adds a size column'
check 'printf "%s" "$outd" | grep -q myrepo-1' 'status --disk still lists the worktree'
check '! COPILOT_AGENT_SESSION_ID=sSt "$BIN/wt-status" --bogus 2>/dev/null' 'status rejects an unknown argument'

echo "== status shows the checked-out branch =="
wsb="$(COPILOT_AGENT_SESSION_ID=sSt2 "$BIN/wt-claim" --repo "$repo" 2>/dev/null)"
git -C "$wsb" checkout -q -b shown-branch
out2="$(COPILOT_AGENT_SESSION_ID=sSt "$BIN/wt-status" 2>&1)"
check 'printf "%s" "$out2" | grep -q BRANCH' 'status has a BRANCH column'
check 'printf "%s" "$out2" | grep -q shown-branch' 'status shows the checked-out branch'

echo "== --mine and the here-marker =="
mine="$(COPILOT_AGENT_SESSION_ID=sSt "$BIN/wt-status" --mine 2>&1)"
check 'printf "%s" "$mine" | grep -q "$(basename "$wSt")"' 'status --mine shows a worktree this session owns'
check '! printf "%s" "$mine" | grep -q "$(basename "$wsb")"' 'status --mine hides other sessions worktrees'
here="$(cd "$wSt" && COPILOT_AGENT_SESSION_ID=sSt "$BIN/wt-status" 2>&1)"
check 'printf "%s" "$here" | grep -q "> $(basename "$wSt")"' 'status marks the worktree you are in with >'

echo "== --porcelain =="
por="$(COPILOT_AGENT_SESSION_ID=sSt "$BIN/wt-status" --porcelain 2>&1)"
check 'printf "%s" "$por" | grep -q "$wSt"' 'porcelain includes the worktree path'
check '! printf "%s" "$por" | grep -q "Worktree pool"' 'porcelain omits the header'
check 'printf "%s" "$por" | grep -q "$(printf "\t")"' 'porcelain output is tab-separated'

echo "== --repo filter and summary line =="
other="$(new_repo otherrepo)"
COPILOT_AGENT_SESSION_ID=sSt3 "$BIN/wt-claim" --repo "$other" >/dev/null 2>&1
scoped="$(COPILOT_AGENT_SESSION_ID=sSt "$BIN/wt-status" --repo "$repo" 2>&1)"
check 'printf "%s" "$scoped" | grep -q myrepo-1' 'status --repo shows the repo worktrees'
check '! printf "%s" "$scoped" | grep -q otherrepo' 'status --repo hides other repos'
check 'printf "%s" "$scoped" | grep -q "yours"' 'status prints a summary line'

report
