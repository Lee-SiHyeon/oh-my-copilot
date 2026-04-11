#!/usr/bin/env bash
# session-end.sh — omc session teardown (refactored: thin orchestrator)
set -uo pipefail

# ---------------------------------------------------------------------------
# Source library modules
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/git-status-parser.sh"
source "${SCRIPT_DIR}/lib/proposal-queue.sh"
source "${SCRIPT_DIR}/lib/readme-sync-guard.sh"

# ---------------------------------------------------------------------------
# Initialize environment
# ---------------------------------------------------------------------------
ensure_state_directories
ensure_learnings_file
log_session_end

# ---------------------------------------------------------------------------
# One-time migration: proposals.json → SQLite proposals table
# ---------------------------------------------------------------------------
migrate_proposals_json_to_sqlite

# ---------------------------------------------------------------------------
# Queue shared-source improvement proposal
# ---------------------------------------------------------------------------
if ! command -v git &>/dev/null; then
  echo "[omc] Git not available, skipping shared-source proposal queue"
else
  declare -a status_lines shared_paths ignored_paths readme_sync_paths
  declare readme_changed=false

  parse_git_status "$PLUGIN_ROOT" status_lines shared_paths ignored_paths readme_sync_paths readme_changed

  enforce_readme_sync_check "$readme_changed" "${readme_sync_paths[@]}"

  if [[ ${#shared_paths[@]} -gt 0 ]]; then
    if ! queue_improvement_candidate; then
      exit 1
    fi
  elif [[ ${#ignored_paths[@]} -gt 0 ]]; then
    ignored_summary="$(printf '%s, ' "${ignored_paths[@]}")"
    ignored_summary="${ignored_summary%, }"
    echo "[omc] Ignoring personal/runtime changes for shared-source proposal queue: ${ignored_summary}"
  else
    echo "[omc] No shared source changes to queue"
  fi
fi

# ---------------------------------------------------------------------------
# Garbage Collection: proposals.json aged-out entries
# ---------------------------------------------------------------------------
garbage_collect_proposals

# ---------------------------------------------------------------------------
# Consolidate
# ---------------------------------------------------------------------------
if [[ -f "$CONSOLIDATE_SCRIPT" ]]; then
  bash "$CONSOLIDATE_SCRIPT" 2>/dev/null
fi
