#!/usr/bin/env bash
# a branch checked out in several repos' worktrees is inferred from the current repo
# shellcheck disable=SC2016,SC2034
# shellcheck source=harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/harness.sh"

repo1="$(new_repo alpha)"
repo2="$(new_repo beta)"

# the same branch name is checked out in a worktree of each repo, which is ambiguous
w1="$(COPILOT_AGENT_SESSION_ID=s1 "$BIN/wt-claim" --repo "$repo1" 2>/dev/null)"
w2="$(COPILOT_AGENT_SESSION_ID=s2 "$BIN/wt-claim" --repo "$repo2" 2>/dev/null)"
git -C "$w1" checkout -q -b shared
git -C "$w2" checkout -q -b shared

echo "== a shared branch is inferred from the current repo =="
check '[ "$(cd "$repo1" && "$BIN/wt-path" shared)" = "$w1" ]' 'positional branch resolves to the current repo (alpha)'
check '[ "$(cd "$repo2" && "$BIN/wt-path" shared)" = "$w2" ]' 'positional branch resolves to the current repo (beta)'
check '[ "$(cd "$repo1" && "$BIN/wt-path" --branch shared)" = "$w1" ]' '--branch resolves to the current repo'

echo "== a shared branch is inferred from the current path =="
check '[ "$(cd "$w2" && "$BIN/wt-path" shared)" = "$w2" ]' 'the worktree you are standing in wins (beta)'
mkdir -p "$w1/sub/dir"
check '[ "$(cd "$w1/sub/dir" && "$BIN/wt-path" shared)" = "$w1" ]' 'a subdirectory of the worktree you are in wins (alpha)'

echo "== inference carries across commands =="
out="$(cd "$repo2" && COPILOT_AGENT_SESSION_ID=sX "$BIN/wt-remove" shared --force --dry-run 2>&1)"
check 'printf "%s" "$out" | grep -q "would remove beta-1"' 'remove infers the current repo worktree'
check '! printf "%s" "$out" | grep -q "alpha-1"' 'remove leaves the other repo worktree out of it'
check '[ -d "$w1" ] && [ -d "$w2" ]' 'the dry run removed nothing'

echo "== an unresolvable ambiguity is reported with the candidates =="
rc=0
( cd "$ROOT" && "$BIN/wt-path" shared ) > "$ROOT/amb.txt" 2>&1 || rc=$?
check '[ "$rc" -ne 0 ]' 'a shared branch with no repo context is rejected'
check 'grep -q "multiple worktrees" "$ROOT/amb.txt"' 'the error explains the conflict'
check 'grep -q "alpha-1" "$ROOT/amb.txt" && grep -q "beta-1" "$ROOT/amb.txt"' 'the error lists both candidates'

echo "== a branch in a single worktree still resolves without any context =="
git -C "$w1" checkout -q -b only-alpha
check '[ "$(cd "$ROOT" && "$BIN/wt-path" only-alpha)" = "$w1" ]' 'a unique branch needs no inference'

report
