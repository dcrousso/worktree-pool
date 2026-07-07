#!/usr/bin/env bash
# normalizing legacy worktree names
# shellcheck disable=SC2016,SC2034
# shellcheck source=harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/harness.sh"

repo="$(new_repo)"

echo "== migrate renames a legacy worktree =="
git -C "$repo" worktree add -q --detach "$WT_POOL_ROOT/myrepo_-99" main
mkdir -p "$WT_POOL_ROOT/myrepo_-99/out"
printf 'x\n' > "$WT_POOL_ROOT/myrepo_-99/out/legacycache"
COPILOT_AGENT_SESSION_ID=sMig "$BIN/wt-migrate" > "$ROOT/mig.txt" 2>&1
check 'grep -q "renamed myrepo_-99 to myrepo-99" "$ROOT/mig.txt"' 'a legacy name is renamed'
check '[ -d "$WT_POOL_ROOT/myrepo-99" ]' 'the worktree exists at the new path'
check '[ ! -e "$WT_POOL_ROOT/myrepo_-99" ]' 'the old path is gone'
check '[ -f "$WT_POOL_ROOT/myrepo-99/out/legacycache" ]' 'the build cache is preserved'
check 'git -C "$repo" worktree list | grep -q myrepo-99' 'git metadata points at the new path'
check 'git -C "$WT_POOL_ROOT/myrepo-99" status >/dev/null 2>&1' 'the migrated worktree is valid'

echo "== migrate is idempotent =="
COPILOT_AGENT_SESSION_ID=sMig "$BIN/wt-migrate" --dry-run > "$ROOT/mig2.txt" 2>&1
check '! grep -q "would rename" "$ROOT/mig2.txt" && grep -q "0 renamed" "$ROOT/mig2.txt"' 'a second run has nothing to do'

report
