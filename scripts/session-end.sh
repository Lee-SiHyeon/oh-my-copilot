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
# STORAGE DESIGN: Two-tier proposal storage is intentional:
#   proposals.json (JSON) — user-visible, auditable queue. Stored in STATE_ROOT for transparency.
#   SQLite DB            — internal improvement candidates, indexed for deduplication.
# JSON is for user review; SQLite is for programmatic processing. Do not consolidate without care.
PROPOSALS_PATH="${STATE_ROOT}/proposals.json"
LOG_PATH="${COPILOT_ROOT}/session.log"
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
TIMESTAMP_ISO="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date '+%Y-%m-%d %H:%M:%S')"
CONSOLIDATE_SCRIPT="${SCRIPT_DIR}/consolidate.sh"

# REFACTOR NOTE (Single Responsibility Principle):
# This script handles multiple concerns and should be split into:
#   lib/git-status-parser.sh  — git status parsing and path classification
#   lib/proposal-queue.sh     — proposal JSON queue management (add_proposal, ensure_proposals_file)
#   lib/readme-sync-guard.sh  — README sync enforcement logic
#   bin/session-end.sh        — thin orchestrator calling the above libs (~50 lines)
# Current size: ~323 lines. Refactoring would improve testability and maintainability.

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
  value="${value//\"/\"\"}"
  printf '%s' "$value"
}

escape_sql() { local v="$1"; v="${v//\'/\'\'}"; v="${v//\"/\"\"}"; printf '%s' "$v"; }

# ---------------------------------------------------------------------------
# Helper: JSON proposal queue
# ---------------------------------------------------------------------------
hash_content() {
  local content="$1"
  if command -v sha256sum &>/dev/null; then
    printf '%s' "$content" | sha256sum | awk '{print $1}'
  elif command -v shasum &>/dev/null; then
    printf '%s' "$content" | shasum -a 256 | awk '{print $1}'
  elif command -v md5sum &>/dev/null; then
    echo "[omc] WARNING: Using weak hash fallback (md5/length). Install sha256sum for reliable deduplication." >&2
    printf '%s' "$content" | md5sum | awk '{print $1}'
  else
    echo "[omc] WARNING: Using weak hash fallback (md5/length). Install sha256sum for reliable deduplication." >&2
    # Absolute fallback: string length + first chars
    printf '%s' "${content:0:8}${#content}"
  fi
}

ensure_proposals_file() {
  if [[ ! -f "$PROPOSALS_PATH" ]]; then
    if ! mkdir -p "$(dirname "$PROPOSALS_PATH")" || ! echo "[]" > "$PROPOSALS_PATH"; then
      echo "[omc] ERROR: Failed to create proposals file at $PROPOSALS_PATH" >&2
      return 1
    fi
  fi
}

add_proposal() {
  local proposal_type="$1"
  local description="$2"
  local file_path="$3"
  local priority="${4:-normal}"
  local suggested_change="${5:-}"
  
  ensure_proposals_file

  # Content hash for deduplication (type + path + change summary)
  local content_hash
  content_hash="$(hash_content "${proposal_type}:${file_path}:${suggested_change}")"

  # flock ensures atomic check-and-insert to prevent duplicate proposals under parallel sessions
  (
    flock -x 200

    # OPTIMIZATION: Current O(N) dedup scan via jq. For high-volume usage, consider migrating
    # proposals to SQLite with: UNIQUE(contentHash) constraint + INSERT OR IGNORE.
    # This would make deduplication O(1) and atomic (also fixing the race condition).
    # Check if this proposal already exists
    if command -v jq &>/dev/null; then
      local existing
      existing="$(jq -r ".[] | select(.contentHash == \"${content_hash}\") | .id" "$PROPOSALS_PATH" 2>/dev/null | head -1)"
      if [[ -n "$existing" ]]; then
        echo "[omc] Proposal already queued (dedup: $content_hash, id: $existing)" >&2
        exit 0
      fi
    fi

    # Generate unique ID (timestamp + hash prefix)
    local proposal_id
    proposal_id="$(date '+%Y%m%d%H%M%S')-${content_hash:0:8}"

    # Build proposal JSON using printf/string manipulation (portable, no jq dependency)
    local proposal
    proposal=$(cat <<EOF
{
  "id": "$proposal_id",
  "timestamp": "$TIMESTAMP_ISO",
  "type": "$proposal_type",
  "description": "$description",
  "filePath": "$file_path",
  "priority": "$priority",
  "suggestedChange": "$suggested_change",
  "contentHash": "$content_hash",
  "status": "pending"
}
EOF
)

    # Append to proposals file (simple array append via temp file)
    if command -v jq &>/dev/null; then
      # Use jq if available for robust JSON handling
      if ! jq ". += [$(printf '%s' "$proposal")]" "$PROPOSALS_PATH" > "${PROPOSALS_PATH}.tmp" 2>/dev/null || \
         ! mv "${PROPOSALS_PATH}.tmp" "$PROPOSALS_PATH"; then
        echo "[omc] ERROR: Failed to update proposals file" >&2
        exit 1
      fi
    else
      # Fallback: manual array append (assumes well-formed JSON)
      local tmp_file="${PROPOSALS_PATH}.tmp"
      {
        head -c -1 "$PROPOSALS_PATH"  # Remove trailing ]
        echo ","
        echo "$proposal"
        echo "]"
      } > "$tmp_file" && mv "$tmp_file" "$PROPOSALS_PATH" || exit 1
    fi

    echo "[omc] Proposal queued ($proposal_type): $description (id: $proposal_id)" >&2
  ) 200>"${PROPOSALS_PATH}.lock"
  return $?
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
# Queue shared-source improvement proposal
# ---------------------------------------------------------------------------
if ! command -v git &>/dev/null; then
  echo "[omc] Git not available, skipping shared-source proposal queue"
else
  cd "$PLUGIN_ROOT" || { echo "[omc] ERROR: Failed to cd to PLUGIN_ROOT='$PLUGIN_ROOT'" >&2; exit 1; }

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
    # README sync is advisory — warn but do not block to avoid disrupting sessions
    echo "[omc] WARNING: README sync recommended before session end: update README.md for ${changed_summary}" >&2
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
