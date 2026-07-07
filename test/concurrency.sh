#!/usr/bin/env bash
# claims never double-own a worktree, even under heavy contention and stale reclaim
# shellcheck disable=SC2016,SC2034
# shellcheck source=harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/harness.sh"

repo="$(new_repo)"
claim() { COPILOT_AGENT_SESSION_ID="$1" "$BIN/wt-claim" --repo "$repo" 2>/dev/null; }

# distinct <dir> <count> checks that every claim wrote a path and all are unique
distinct() {
	cat "$1"/[0-9]* > "$1/all"
	local d t
	d="$(sort -u "$1/all" | wc -l | tr -d ' ')"
	t="$(wc -l < "$1/all" | tr -d ' ')"
	[ "$d" = "$t" ] && [ "$t" = "$2" ]
}

make_stale() {
	local lk
	for lk in "$LOCKS"/*.lock; do
		[ -e "$lk" ] || continue
		sed "s/^heartbeat=.*/heartbeat=$(( $(date +%s) - 19 * 3600 ))/" "$lk" > "$lk.t" && mv "$lk.t" "$lk"
	done
}

echo "== fresh concurrent claims are distinct =="
mkdir -p "$ROOT/a"
for i in 1 2 3 4 5 6 7 8 9 10; do ( claim "f$i" > "$ROOT/a/$i" ) & done
wait
check 'distinct "$ROOT/a" 10' '10 fresh concurrent claims yield 10 distinct worktrees'

echo "== concurrent reclaim is atomic =="
# make every worktree reclaimable, then hammer with more claimers than worktrees
make_stale
mkdir -p "$ROOT/b"
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do ( claim "s$i" > "$ROOT/b/$i" ) & done
wait
check 'distinct "$ROOT/b" 12' '12 concurrent claimers never double-own a reclaimed worktree'

echo "== with_lock provides mutual exclusion =="
# two holders each record enter/exit around a sleep, a working mutex must never interleave them
mx="$ROOT/mx.d"
seqf="$ROOT/mxseq"
: > "$seqf"
hold() { /bin/bash -c 'source "$1"; with_lock "$2" /bin/sh -c "printf E$3\\\\n >> $4; sleep 0.4; printf X$3\\\\n >> $4"' _ "$BIN/wt-lib.sh" "$mx" "$1" "$seqf"; }
hold 1 &
sleep 0.1
hold 2 &
wait
mxorder="$(tr '\n' ' ' < "$seqf")"
check '[ "$mxorder" = "E1 X1 E2 X2 " ] || [ "$mxorder" = "E2 X2 E1 X1 " ]' "with_lock serializes critical sections (got: $mxorder)"

echo "== with_lock recovers a mutex from a crashed holder =="
mkdir -p "$ROOT/stale.mx"
touch -t 202001010000 "$ROOT/stale.mx"
check '/bin/bash -c '"'"'source "$0"; with_lock "$1" true'"'"' "$BIN/wt-lib.sh" "$ROOT/stale.mx"' 'a minute-old mutex is reclaimed'

report
