#!/usr/bin/env bash
# the global build lock serializes heavy builds
# shellcheck disable=SC2016,SC2034
# shellcheck source=harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/harness.sh"

repo="$(new_repo)"
w1="$(COPILOT_AGENT_SESSION_ID=b1 "$BIN/wt-claim" --repo "$repo" 2>/dev/null)"
w2="$(COPILOT_AGENT_SESSION_ID=b2 "$BIN/wt-claim" --repo "$repo" 2>/dev/null)"

seq_file="$ROOT/seq"
: > "$seq_file"
build() { COPILOT_AGENT_SESSION_ID="$1" "$BIN/wt-build" -- /bin/sh -c "printf 'S$2\n' >> '$seq_file'; sleep 1; printf 'E$2\n' >> '$seq_file'"; }

echo "== serialization =="
( cd "$w1" && build b1 1 ) >/dev/null 2>&1 &
p1=$!
sleep 0.5
( cd "$w2" && build b2 2 ) >/dev/null 2>&1 &
p2=$!
wait "$p1"
wait "$p2"

# a serialized run is S1 E1 S2 E2, an overlapping one would interleave the S and E marks
order="$(tr '\n' ' ' < "$seq_file")"
check '[ "$order" = "S1 E1 S2 E2 " ] || [ "$order" = "S2 E2 S1 E1 " ]' "the build lock serializes builds (got: $order)"

echo "== build keeps the owning worktree alive =="
lk="$LOCKS/$(basename "$w1").lock"
sed "s/^heartbeat=.*/heartbeat=1/" "$lk" > "$lk.t" && mv "$lk.t" "$lk"
( cd "$w1" && COPILOT_AGENT_SESSION_ID=b1 "$BIN/wt-build" -- true ) >/dev/null 2>&1
hb="$(sed -n 's/^heartbeat=//p' "$lk")"
check '[ "$hb" -gt 1000000000 ]' 'building in an owned worktree refreshes its heartbeat'

echo "== exit codes propagate =="
( cd "$w1" && COPILOT_AGENT_SESSION_ID=b1 "$BIN/wt-build" -- /bin/sh -c 'exit 7' ) >/dev/null 2>&1
rc=$?
check '[ "$rc" = 7 ]' 'the build exit code propagates through wt-build'

echo "== build --branch runs in the worktree on that branch =="
wbb="$(COPILOT_AGENT_SESSION_ID=bBr "$BIN/wt-claim" --repo "$repo" 2>/dev/null)"
git -C "$wbb" checkout -q -b build-here
COPILOT_AGENT_SESSION_ID=bBr "$BIN/wt-build" --branch build-here -- /bin/sh -c 'printf built > ran-here' >/dev/null 2>&1
check '[ -f "$wbb/ran-here" ]' 'build --branch runs the command inside that worktree'

echo "== build with a positional target runs there =="
wbp="$(COPILOT_AGENT_SESSION_ID=bPos "$BIN/wt-claim" --repo "$repo" 2>/dev/null)"
git -C "$wbp" checkout -q -b build-pos
COPILOT_AGENT_SESSION_ID=bPos "$BIN/wt-build" build-pos -- /bin/sh -c 'printf built > ran-pos' >/dev/null 2>&1
check '[ -f "$wbp/ran-pos" ]' 'build <branch> (positional) runs in that worktree'

report
