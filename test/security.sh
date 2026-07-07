#!/usr/bin/env bash
# a note is untrusted input, so it must never inject a lock field or run code
# shellcheck disable=SC2016,SC2034
# shellcheck source=harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/harness.sh"

repo="$(new_repo)"

echo "== acquire flattens the note =="
l="$ROOT/probe.lock"
COPILOT_AGENT_SESSION_ID=sess-x lib acquire "$l" /r /w detached:main "$(printf 'evil\nsession=HACKED')" >/dev/null 2>&1
check '[ "$(lib read_field "$l" session)" = sess-x ]' 'a newline in the note cannot inject a session field'
check '[ "$(lib read_field "$l" note)" = "evilsession=HACKED" ]' 'the note is flattened to one line'

echo "== a note cannot execute code =="
marker="$ROOT/pwned"
COPILOT_AGENT_SESSION_ID=sess-y "$BIN/wt-claim" --repo "$repo" --note "\$(touch $marker)\`touch $marker\`" >/dev/null 2>&1
check '[ ! -e "$marker" ]' 'command substitution in a note does not execute'

report
