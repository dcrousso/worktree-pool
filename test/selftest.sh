#!/usr/bin/env bash
# runs every test file in this directory and reports a combined result
# each test file is also runnable on its own, e.g. `bash test/claim.sh`
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
self="$(basename "${BASH_SOURCE[0]}")"

total_pass=0
total_fail=0
failed=0

for t in "$here"/*.sh; do
	name="$(basename "$t")"
	case "$name" in
		harness.sh|"$self") continue ;;
	esac

	out="$(/bin/bash "$t" 2>&1)"
	rc=$?
	counts="$(printf '%s\n' "$out" | sed -n 's/^RESULT: \([0-9][0-9]*\) passed, \([0-9][0-9]*\) failed$/\1 \2/p')"
	# shellcheck disable=SC2086
	set -- $counts
	p="${1:-0}"
	f="${2:-0}"
	total_pass=$(( total_pass + p ))
	total_fail=$(( total_fail + f ))

	if [ "$rc" -eq 0 ]; then
		printf 'PASS  %-12s %s ok\n' "${name%.sh}" "$p"
	else
		printf 'FAIL  %-12s %s ok, %s failed\n' "${name%.sh}" "$p" "$f"
		fails="$(printf '%s\n' "$out" | grep '^FAIL')"
		[ -n "$fails" ] && printf '%s\n' "$fails" | sed 's/^/        /'
		[ -z "$fails" ] && printf '%s\n' "$out" | tail -5 | sed 's/^/        /'
		failed=1
	fi
done

printf '\nTOTAL: %d passed, %d failed\n' "$total_pass" "$total_fail"
[ "$failed" -eq 0 ]
