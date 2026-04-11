#!/usr/bin/env bash
# readme-sync-guard.sh — README sync enforcement logic
set -uo pipefail

# Load dependencies
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# ---------------------------------------------------------------------------
# Shared-source improvement proposal management
# ---------------------------------------------------------------------------
ensure_improvement_candidates_table() {
  if ! command -v sqlite3 &>/dev/null; then
    echo "[omc] sqlite3 is required to queue shared-source improvement proposals" >&2
    return 1
  fi

  if [[ ! -f "$DB_PATH" && -f "${SCRIPT_DIR}/init-memory.sh" ]]; then
    bash "${SCRIPT_DIR}/init-memory.sh" "$DB_PATH" >/dev/null 2>&1 || true
  fi

  sqlite3 "$DB_PATH" <<'SQL'
CREATE TABLE IF NOT EXISTS improvement_candidates (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at        DATETIME DEFAULT CURRENT_TIMESTAMP,
    proposal_kind     TEXT    DEFAULT 'shared_source_change',
    plugin_root       TEXT    NOT NULL,
    git_remote_name   TEXT,
    git_remote_url    TEXT,
    git_branch        TEXT,
    head_commit       TEXT,
    changed_paths     TEXT    NOT NULL,
    status_snapshot   TEXT    NOT NULL
);
SQL
  return $?
}

resolve_git_remote_name() {
  local upstream
  upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
  if [[ -n "$upstream" && "$upstream" == */* ]]; then
    printf '%s\n' "${upstream%%/*}"
    return 0
  fi

  if git remote get-url origin >/dev/null 2>&1; then
    printf '%s\n' "origin"
    return 0
  fi

  git remote 2>/dev/null | head -n 1
}

queue_improvement_candidate() {
  local remote_name remote_url branch_name head_commit changed_paths_snapshot status_snapshot changed_summary
  local proposal_description

  if ! ensure_improvement_candidates_table; then
    return 1
  fi

  remote_name="$(resolve_git_remote_name)"
  remote_url=""
  if [[ -n "$remote_name" ]]; then
    remote_url="$(git remote get-url "$remote_name" 2>/dev/null || true)"
  fi

  branch_name="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  head_commit="$(git rev-parse HEAD 2>/dev/null || true)"
  changed_paths_snapshot="$(printf '%s\n' "${shared_paths[@]}")"
  status_snapshot="$(printf '%s\n' "${status_lines[@]}")"

  # Record in SQLite (existing safe mechanism)
  if ! sqlite3 "$DB_PATH" "
INSERT INTO improvement_candidates (
    proposal_kind,
    plugin_root,
    git_remote_name,
    git_remote_url,
    git_branch,
    head_commit,
    changed_paths,
    status_snapshot
) VALUES (
    'shared_source_change',
    '$(sql_escape "$PLUGIN_ROOT")',
    '$(sql_escape "$remote_name")',
    '$(sql_escape "$remote_url")',
    '$(sql_escape "$branch_name")',
    '$(sql_escape "$head_commit")',
    '$(sql_escape "$changed_paths_snapshot")',
    '$(sql_escape "$status_snapshot")'
);"; then
    echo "[omc] Failed to record shared-source improvement proposal in SQLite" >&2
    return 1
  fi

  # Also record in JSON proposals file for transparency (NEW)
  changed_summary="$(printf '%s, ' "${shared_paths[@]}")"
  changed_summary="${changed_summary%, }"
  proposal_description="shared-source changes detected: $changed_summary (branch: $branch_name, remote: $remote_name)"

  if ! add_proposal "shared-source-change" "$proposal_description" "$PLUGIN_ROOT" "normal" "$changed_paths_snapshot"; then
    echo "[omc] Warning: Failed to record proposal in JSON queue (continuing with SQLite record)" >&2
  fi

  echo "[omc] Queued shared-source improvement proposal in user-local memory for: ${changed_summary}"
}

# ---------------------------------------------------------------------------
# README sync guard enforcement
# ---------------------------------------------------------------------------
enforce_readme_sync_check() {
  local readme_sync_paths=("$@")
  local readme_changed="$1"
  shift

  if [[ ${#readme_sync_paths[@]} -gt 0 && "$readme_changed" != true ]]; then
    changed_summary="$(printf '%s, ' "${readme_sync_paths[@]}")"
    changed_summary="${changed_summary%, }"
    # README sync is advisory — warn but do not block to avoid disrupting sessions
    echo "[omc] WARNING: README sync recommended before session end: update README.md for ${changed_summary}" >&2
  fi
}
