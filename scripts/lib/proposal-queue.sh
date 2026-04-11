#!/usr/bin/env bash
# proposal-queue.sh — add_proposal, proposals.json management, GC
set -uo pipefail

# Load dependencies
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# ---------------------------------------------------------------------------
# Helper: JSON proposal queue management
# ---------------------------------------------------------------------------
ensure_proposals_file() {
  if [[ ! -f "$PROPOSALS_PATH" ]]; then
    if ! mkdir -p "$(dirname "$PROPOSALS_PATH")" || ! echo "[]" > "$PROPOSALS_PATH"; then
      echo "[omc] ERROR: Failed to create proposals file at $PROPOSALS_PATH" >&2
      return 1
    fi
  fi
}

# ---------------------------------------------------------------------------
# One-time migration: proposals.json → SQLite proposals table
# ---------------------------------------------------------------------------
migrate_proposals_json_to_sqlite() {
  command -v sqlite3 &>/dev/null || return 0
  command -v jq &>/dev/null || return 0
  [[ -f "$DB_PATH" ]] || return 0
  [[ -f "$PROPOSALS_PATH" ]] || return 0

  # Check if migration is needed (flag file)
  local migration_flag="${STATE_ROOT}/.proposals_migrated"
  [[ -f "$migration_flag" ]] && return 0

  # Ensure proposals table exists
  sqlite3 "$DB_PATH" "CREATE TABLE IF NOT EXISTS proposals (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    content_hash TEXT UNIQUE NOT NULL,
    type TEXT NOT NULL,
    content TEXT NOT NULL,
    status TEXT DEFAULT 'pending',
    priority TEXT DEFAULT 'normal',
    file_path TEXT,
    suggested_change TEXT,
    created_at TEXT DEFAULT (datetime('now')),
    resolved_at TEXT
  );" 2>/dev/null || return 0

  local count
  count=$(jq 'length' "$PROPOSALS_PATH" 2>/dev/null || echo "0")
  if (( count == 0 )); then
    touch "$migration_flag"
    return 0
  fi

  local migrated=0
  local skipped=0
  # Read each proposal from JSON and insert into SQLite
  for i in $(seq 0 $(( count - 1 ))); do
    local p_hash p_type p_content p_status p_priority p_filepath p_change p_created
    p_hash=$(jq -r ".[$i].contentHash // empty" "$PROPOSALS_PATH" 2>/dev/null)
    p_type=$(jq -r ".[$i].type // \"unknown\"" "$PROPOSALS_PATH" 2>/dev/null)
    p_content=$(jq -r ".[$i].description // \"\"" "$PROPOSALS_PATH" 2>/dev/null)
    p_status=$(jq -r ".[$i].status // \"pending\"" "$PROPOSALS_PATH" 2>/dev/null)
    p_priority=$(jq -r ".[$i].priority // \"normal\"" "$PROPOSALS_PATH" 2>/dev/null)
    p_filepath=$(jq -r ".[$i].filePath // \"\"" "$PROPOSALS_PATH" 2>/dev/null)
    p_change=$(jq -r ".[$i].suggestedChange // \"\"" "$PROPOSALS_PATH" 2>/dev/null)
    p_created=$(jq -r ".[$i].timestamp // empty" "$PROPOSALS_PATH" 2>/dev/null)

    [[ -z "$p_hash" ]] && { (( skipped++ )) || true; continue; }

    sqlite3 "$DB_PATH" "INSERT OR IGNORE INTO proposals (content_hash, type, content, status, priority, file_path, suggested_change, created_at)
      VALUES ('$(sql_escape "$p_hash")', '$(sql_escape "$p_type")', '$(sql_escape "$p_content")', '$(sql_escape "$p_status")', '$(sql_escape "$p_priority")', '$(sql_escape "$p_filepath")', '$(sql_escape "$p_change")', '$(sql_escape "$p_created")');" 2>/dev/null && (( migrated++ )) || (( skipped++ )) || true
  done

  touch "$migration_flag"
  echo "[omc] proposals.json → SQLite migration: ${migrated} migrated, ${skipped} skipped (duplicates)" >&2
}

# ---------------------------------------------------------------------------
# Add a proposal to the queue
# ---------------------------------------------------------------------------
add_proposal() {
  # jq is required for proposal management
  if ! command -v jq &>/dev/null; then
    echo "[omc] jq is required for proposal management. Install jq." >&2
    return 1
  fi

  local proposal_type="$1"
  local description="$2"
  local file_path="$3"
  local priority="${4:-normal}"
  local suggested_change="${5:-}"

  ensure_proposals_file

  # Content hash for deduplication (type + path + change summary)
  local content_hash
  content_hash="$(hash_content "${proposal_type}:${file_path}:${suggested_change}")"

  local proposal_id
  proposal_id="$(date '+%Y%m%d%H%M%S')-${content_hash:0:8}"

  # PRIMARY: SQLite proposals table (O(1) dedup via UNIQUE constraint on content_hash)
  if command -v sqlite3 &>/dev/null && [[ -f "$DB_PATH" ]]; then
    # Ensure proposals table exists
    sqlite3 "$DB_PATH" "CREATE TABLE IF NOT EXISTS proposals (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      content_hash TEXT UNIQUE NOT NULL,
      type TEXT NOT NULL,
      content TEXT NOT NULL,
      status TEXT DEFAULT 'pending',
      priority TEXT DEFAULT 'normal',
      file_path TEXT,
      suggested_change TEXT,
      created_at TEXT DEFAULT (datetime('now')),
      resolved_at TEXT
    );" 2>/dev/null || true

    local insert_changes
    insert_changes=$(sqlite3 "$DB_PATH" "INSERT OR IGNORE INTO proposals (content_hash, type, content, priority, file_path, suggested_change)
      VALUES ('$(sql_escape "$content_hash")', '$(sql_escape "$proposal_type")', '$(sql_escape "$description")', '$(sql_escape "$priority")', '$(sql_escape "$file_path")', '$(sql_escape "$suggested_change")');
      SELECT changes();" 2>/dev/null || echo "0")

    if (( insert_changes == 0 )); then
      echo "[omc] Proposal already queued (dedup via SQLite: $content_hash)" >&2
      return 0
    fi
  fi

  # SECONDARY: JSON proposals file for transparency/audit trail
  # flock ensures atomic check-and-insert to prevent duplicate proposals under parallel sessions
  (
    flock -x 200

    # Build proposal JSON
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

    # Append to proposals file (jq is required, checked at function entry)
    if ! jq ". += [$(printf '%s' "$proposal")]" "$PROPOSALS_PATH" > "${PROPOSALS_PATH}.tmp" 2>/dev/null || \
       ! mv "${PROPOSALS_PATH}.tmp" "$PROPOSALS_PATH"; then
      echo "[omc] WARNING: Failed to update proposals JSON file (SQLite record exists)" >&2
    fi

    echo "[omc] Proposal queued ($proposal_type): $description (id: $proposal_id)" >&2
  ) 200>"${PROPOSALS_PATH}.lock"
  return $?
}

# ---------------------------------------------------------------------------
# Garbage Collection: proposals.json aged-out entries
# ---------------------------------------------------------------------------
garbage_collect_proposals() {
  if command -v jq &>/dev/null && [[ -f "$PROPOSALS_PATH" ]]; then
    (
      flock -x 200
      _gc_before=$(jq 'length' "$PROPOSALS_PATH" 2>/dev/null || echo "0")
      # Remove entries with status="done" older than 30 days
      jq '[.[] | select(
        (.status == "done" and
         (now - (.timestamp | fromdateiso8601) > (30 * 86400)))
        | not
      )]' "$PROPOSALS_PATH" > "${PROPOSALS_PATH}.gc_tmp" 2>/dev/null
      if [[ -s "${PROPOSALS_PATH}.gc_tmp" ]]; then
        mv "${PROPOSALS_PATH}.gc_tmp" "$PROPOSALS_PATH"
        _gc_after=$(jq 'length' "$PROPOSALS_PATH" 2>/dev/null || echo "0")
        _gc_removed=$(( _gc_before - _gc_after ))
        if (( _gc_removed > 0 )); then
          echo "[omc] GC: proposals.json — ${_gc_removed} done entries removed (>30 days)" >&2
        fi
      else
        rm -f "${PROPOSALS_PATH}.gc_tmp"
      fi
    ) 200>"${PROPOSALS_PATH}.lock"
  fi
}
