#!/usr/bin/env bash
# unit tests for the pure helpers in wt-lib.sh
# shellcheck disable=SC2016,SC2034
# shellcheck source=harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/harness.sh"

repo="$(new_repo)"

echo "== repo_key =="
check '[ "$(lib repo_key /a/b/playwright)" = playwright ]' 'repo_key drops the trailing newline'
check '[ "$(lib repo_key "/a/b/my repo")" = my_repo ]'     'repo_key sanitizes spaces'
check '[ "$(lib repo_key /a/b/foo_bar)" = foo_bar ]'       'repo_key keeps underscores'

echo "== default_base =="
check '[ "$(lib default_base "$repo")" = main ]' 'default_base finds main'

echo "== session identity =="
check '[ "$(WT_SESSION_ID=custom-xyz sid)" = custom-xyz ]' 'WT_SESSION_ID overrides the identity'
check '[ "$(WT_SESSION_ID= COPILOT_AGENT_SESSION_ID=cop-1 sid)" = cop-1 ]' 'an agent variable is detected'
check '[ "$(WT_SESSION_ID= COPILOT_AGENT_SESSION_ID= TERM_SESSION_ID=term-9 sid)" = term-9 ]' 'the terminal session id is a fallback'
check '[ -n "$(WT_SESSION_ID= COPILOT_AGENT_SESSION_ID= TERM_SESSION_ID= sid)" ]' 'the final fallback is non-empty'
check '[ "$(WT_SESSION_ID="$(printf "x\ny")" sid)" = xy ]' 'the identity strips embedded newlines'

echo "== human_age =="
now="$(date +%s)"
check '[ "$(lib human_age $((now - 30)))" = 0m ]'     'human_age of a recent time is 0m'
check '[ "$(lib human_age $((now - 7200)))" = 2h ]'   'human_age reports hours'
check '[ "$(lib human_age $((now - 172800)))" = 2d ]' 'human_age reports days'
check '[ "$(lib human_age garbage)" = "?" ]'          'human_age rejects a non-number'

echo "== lock_is_stale =="
lk="$ROOT/probe.lock"
printf 'heartbeat=%s\n' "$(( now - 19 * 3600 ))" > "$lk"
check 'lib lock_is_stale "$lk"'   'stale when the heartbeat is old'
printf 'heartbeat=%s\n' "$now" > "$lk"
check '! lib lock_is_stale "$lk"' 'fresh when the heartbeat is recent'
printf 'session=x\n' > "$lk"
check '! lib lock_is_stale "$lk"' 'not stale when there is no heartbeat'

echo "== worktree selectors =="
check '! lib normalize_pool_worktree plainname 2>/dev/null' 'normalize_pool_worktree rejects a non-pool name'
check '! lib find_pool_worktree_by_branch ghost-branch 2>/dev/null' 'find_pool_worktree_by_branch fails when nothing matches'
check '! lib is_pool_worktree_token plainname' 'is_pool_worktree_token rejects a non-pool name'
check '! lib is_pool_worktree_token ghost-9' 'is_pool_worktree_token rejects a missing pool worktree'

report
