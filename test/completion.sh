#!/usr/bin/env bash
# the wt bash completion
# shellcheck disable=SC2016,SC2034,SC2207
# shellcheck source=harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/harness.sh"

repo="$(new_repo)"
w="$(COPILOT_AGENT_SESSION_ID=sC "$BIN/wt-claim" --repo "$repo" 2>/dev/null)"
git -C "$w" checkout -q -b compl-branch
name="$(basename "$w")"

# shellcheck source=/dev/null
source "$BIN/wt-completion.bash"

# comp <words...> runs the completion for the given command line (last word is the cursor)
comp() {
	COMP_WORDS=("$@")
	COMP_CWORD=$(( $# - 1 ))
	COMPREPLY=()
	_wt
	printf '%s\n' "${COMPREPLY[@]}"
}

echo "== subcommands =="
check 'comp wt "" | grep -qx release' 'completes subcommands'
check 'comp wt cl | grep -qx claim' 'completes a subcommand prefix'

echo "== positional targets =="
check 'comp wt release "" | grep -qx "$name"' 'release completes worktree names'
check 'comp wt release "" | grep -qx compl-branch' 'release completes checked-out branches'
check 'comp wt path "" | grep -qx "$name"' 'path completes worktree names'
check 'comp wt claim "" | grep -qx compl-branch' 'claim completes branches'

echo "== flags and flag values =="
check 'comp wt release - | grep -q -- --worktree' 'release completes flags'
check 'comp wt build --branch "" | grep -qx compl-branch' 'build --branch completes branches'
check 'comp wt status - | grep -q -- --mine' 'status completes --mine'

report
