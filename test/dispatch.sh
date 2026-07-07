#!/usr/bin/env bash
# the `wt` dispatcher and argument handling
# shellcheck disable=SC2016,SC2034
# shellcheck source=harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/harness.sh"

echo "== dispatcher =="
check '"$BIN/wt" help 2>&1 | grep -q claim' 'wt help lists the commands'
check 'COPILOT_AGENT_SESSION_ID=sD "$BIN/wt" status 2>&1 | grep -q "Worktree pool"' 'wt status runs through the dispatcher'
check '"$BIN/wt" bogus 2>&1 | grep -q "unknown command"' 'wt rejects an unknown command'

echo "== argument validation =="
check '! "$BIN/wt-claim" --repo 2>/dev/null' 'a missing option value is rejected'
check '"$BIN/wt-claim" --bogus 2>&1 | grep -q "unknown argument"' 'an unknown argument is rejected'

report
