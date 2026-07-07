#!/usr/bin/env bash
# wt-doctor health check and cleanup
# shellcheck disable=SC2016,SC2034
# shellcheck source=harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/harness.sh"

repo="$(new_repo)"

echo "== a healthy pool reports healthy =="
w="$(COPILOT_AGENT_SESSION_ID=sDoc "$BIN/wt-claim" --repo "$repo" 2>/dev/null)"
check '"$BIN/wt-doctor" >/dev/null 2>&1' 'doctor exits 0 on a healthy pool'

echo "== an orphaned lock is detected and fixed =="
lock="$LOCKS/$(basename "$w").lock"
rm -rf "$w"
rc=0
"$BIN/wt-doctor" >/dev/null 2>&1 || rc=$?
check '[ "$rc" -ne 0 ]' 'doctor exits nonzero when a lock is orphaned'
check '"$BIN/wt-doctor" 2>&1 | grep -q "orphaned lock"' 'doctor reports the orphaned lock'
check '[ -e "$lock" ]' 'doctor without --fix leaves the lock in place'
"$BIN/wt-doctor" --fix >/dev/null 2>&1
check '[ ! -e "$lock" ]' 'doctor --fix removes the orphaned lock'

echo "== a leftover mutex is detected and fixed =="
w2="$(COPILOT_AGENT_SESSION_ID=sDoc2 "$BIN/wt-claim" --repo "$repo" 2>/dev/null)"
mx="$LOCKS/$(basename "$w2").lock.mx"
mkdir -p "$mx"
check '"$BIN/wt-doctor" 2>&1 | grep -q "leftover mutex"' 'doctor reports a leftover mutex'
"$BIN/wt-doctor" --fix >/dev/null 2>&1
check '[ ! -d "$mx" ]' 'doctor --fix removes the leftover mutex'

echo "== healthy again after fixing =="
check '"$BIN/wt-doctor" >/dev/null 2>&1' 'doctor is happy once the pool is clean'

report
