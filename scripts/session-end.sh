#!/usr/bin/env bash
# session-end.sh — omc session teardown (ported from session-end.ps1)
set -uo pipefail

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(dirname "$SCRIPT_DIR")"
COPILOT_ROOT="${HOME}/.copilot"
STATE_ROOT="${HOME}/.copilot/oh-my-copilot"
DB_PATH="${STATE_ROOT}/omc-memory.db"
LEARN_PATH="${STATE_ROOT}/LEARNINGS.md"
LOG_PATH="${COPILOT_ROOT}/session.log"
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
CONSOLIDATE_SCRIPT="${SCRIPT_DIR}/consolidate.sh"

# ---------------------------------------------------------------------------
# Ensure directories exist
# ---------------------------------------------------------------------------
mkdir -p "$STATE_ROOT"
mkdir -p "$COPILOT_ROOT"

# ---------------------------------------------------------------------------
# Ensure LEARNINGS.md exists
# ---------------------------------------------------------------------------
if [[ ! -f "$LEARN_PATH" ]]; then
  touch "$LEARN_PATH"
fi

# ---------------------------------------------------------------------------
# Log session end
# ---------------------------------------------------------------------------
echo "[$TIMESTAMP] SESSION_END cwd=$(pwd)" >> "$LOG_PATH"

# ---------------------------------------------------------------------------
# Helper: shared-path filter
# ---------------------------------------------------------------------------
normalize_status_path() {
  local line="$1"
  local raw_path="${line:3}"

  if [[ "$raw_path" == *" -> "* ]]; then
    raw_path="${raw_path##* -> }"
  fi

  raw_path="${raw_path#\"}"
  raw_path="${raw_path%\"}"
  raw_path="${raw_path## }"
  raw_path="${raw_path%% }"

  printf '%s\n' "$raw_path"
}

is_shared_path() {
  local p="$1"
  [[ "$p" =~ ^agents/   ]] || [[ "$p" =~ ^scripts/ ]] ||
  [[ "$p" == "hooks.json"      ]] || [[ "$p" == "plugin.json"  ]] ||
  [[ "$p" == "LEARNINGS.md"    ]] || [[ "$p" == "README.md"    ]] ||
  [[ "$p" == "local/README.md" ]] || [[ "$p" == ".gitignore"   ]]
}

is_readme_sync_guard_path() {
  local p="$1"
  [[ "$p" =~ ^agents/ ]] || [[ "$p" =~ ^scripts/ ]] ||
  [[ "$p" == "hooks.json" ]] || [[ "$p" == "plugin.json" ]] ||
  [[ "$p" == "local/README.md" ]] || [[ "$p" == ".gitignore" ]]
}

sql_escape() {
  local value="${1-}"
  value="${value//\'/\'\'}"
  printf '%s' "$value"
}

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
    echo "[omc] Failed to record shared-source improvement proposal" >&2
    return 1
  fi

  changed_summary="$(printf '%s, ' "${shared_paths[@]}")"
  changed_summary="${changed_summary%, }"
  echo "[omc] Queued shared-source improvement proposal in user-local memory for: ${changed_summary}"
}

# ---------------------------------------------------------------------------
# Queue shared-source improvement proposal
# ---------------------------------------------------------------------------
if ! command -v git &>/dev/null; then
  echo "[omc] Git not available, skipping shared-source proposal queue"
else
  cd "$PLUGIN_ROOT"

  # Parse git status into changed paths
  mapfile -t status_lines < <(git status --porcelain --untracked-files=all 2>/dev/null)

  shared_paths=()
  ignored_paths=()
  readme_sync_paths=()
  readme_changed=false
  for line in "${status_lines[@]}"; do
    raw_path="$(normalize_status_path "$line")"
    [[ -n "$raw_path" ]] || continue

    if is_shared_path "$raw_path"; then
      shared_paths+=("$raw_path")
    else
      ignored_paths+=("$raw_path")
    fi

    if [[ "$raw_path" == "README.md" ]]; then
      readme_changed=true
    fi

    if is_readme_sync_guard_path "$raw_path"; then
      readme_sync_paths+=("$raw_path")
    fi
  done

  if [[ ${#readme_sync_paths[@]} -gt 0 && "$readme_changed" != true ]]; then
    changed_summary="$(printf '%s, ' "${readme_sync_paths[@]}")"
    changed_summary="${changed_summary%, }"
    echo "[omc] README sync required before session end: update README.md for ${changed_summary}" >&2
    exit 1
  fi

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
# Consolidate
# ---------------------------------------------------------------------------
if [[ -f "$CONSOLIDATE_SCRIPT" ]]; then
  bash "$CONSOLIDATE_SCRIPT" 2>/dev/null
fi
