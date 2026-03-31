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

migrate_proposals_json_to_sqlite

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

    # Append to proposals file
    if command -v jq &>/dev/null; then
      if ! jq ". += [$(printf '%s' "$proposal")]" "$PROPOSALS_PATH" > "${PROPOSALS_PATH}.tmp" 2>/dev/null || \
         ! mv "${PROPOSALS_PATH}.tmp" "$PROPOSALS_PATH"; then
        echo "[omc] WARNING: Failed to update proposals JSON file (SQLite record exists)" >&2
      fi
    else
      # Fallback: manual array append (assumes well-formed JSON)
      local tmp_file="${PROPOSALS_PATH}.tmp"
      {
        head -c -1 "$PROPOSALS_PATH"
        echo ","
        echo "$proposal"
        echo "]"
      } > "$tmp_file" && mv "$tmp_file" "$PROPOSALS_PATH" || true
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
# Agent usage tracking for Q-Learning rewards
# ---------------------------------------------------------------------------
# Collect agent usage from this session and record in agent_usage_log.
# Heuristic: parse session.log for agent spawn events, or use LEARNINGS.md
# entries from the current session as a proxy for agent activity.
#
# Outcome determination:
#   - success (reward=1.0):  session ended normally, no error keywords in recent log
#   - partial (reward=0.5):  session ended but with warnings/retries
#   - failure (reward=-0.5): error patterns detected in session log

track_agent_usage() {
  command -v sqlite3 &>/dev/null || return 0
  [[ -f "$DB_PATH" ]] || return 0

  # Generate a unique session ID for this session
  local session_id
  session_id="$(date '+%Y%m%d%H%M%S')-$$"

  # Ensure table exists
  sqlite3 "$DB_PATH" "CREATE TABLE IF NOT EXISTS agent_usage_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL,
    task_signature TEXT NOT NULL,
    agent_id TEXT NOT NULL,
    outcome TEXT DEFAULT 'unknown',
    reward REAL DEFAULT 0.0,
    created_at TEXT DEFAULT (datetime('now'))
  );" 2>/dev/null || true

  # Heuristic: scan recent session log entries for agent-related patterns
  # Look for lines logged AFTER the session start (last SESSION_START entry)
  local log_file="$LOG_PATH"
  [[ -f "$log_file" ]] || return 0

  # Extract agent mentions from recent log and LEARNINGS.md
  local agents_used=()
  local task_sigs=()

  # Pattern: agent names that match known Q-table entries
  # Map detected patterns to (task_signature, agent_id) pairs
  local -A agent_task_map=(
    ["hephaestus"]="code_complex"
    ["sisyphus-junior"]="code_simple"
    ["prometheus"]="planning"
    ["oracle"]="debugging"
    ["nlm-researcher"]="research"
    ["librarian"]="research"
    ["explore"]="codebase_search"
    ["metis"]="planning"
    ["momus"]="planning"
  )

  # Scan LEARNINGS.md for agent mentions in today's entries
  if [[ -f "$LEARN_PATH" ]]; then
    local today_pattern
    today_pattern="$(date '+%Y-%m-%d')"
    while IFS= read -r learn_line; do
      for agent_name in "${!agent_task_map[@]}"; do
        if echo "$learn_line" | grep -qi "$agent_name"; then
          # Check if we already added this agent
          local already_added=false
          for existing in "${agents_used[@]+"${agents_used[@]}"}"; do
            [[ "$existing" == "$agent_name" ]] && already_added=true && break
          done
          if [[ "$already_added" != true ]]; then
            agents_used+=("$agent_name")
            task_sigs+=("${agent_task_map[$agent_name]}")
          fi
        fi
      done
    done < <(grep "$today_pattern" "$LEARN_PATH" 2>/dev/null || true)
  fi

  # Also scan session log for recent agent references
  if [[ -f "$log_file" ]]; then
    local recent_lines
    recent_lines="$(tail -50 "$log_file" 2>/dev/null || true)"
    for agent_name in "${!agent_task_map[@]}"; do
      if echo "$recent_lines" | grep -qi "$agent_name"; then
        local already_added=false
        for existing in "${agents_used[@]+"${agents_used[@]}"}"; do
          [[ "$existing" == "$agent_name" ]] && already_added=true && break
        done
        if [[ "$already_added" != true ]]; then
          agents_used+=("$agent_name")
          task_sigs+=("${agent_task_map[$agent_name]}")
        fi
      fi
    done
  fi

  # Determine outcome based on session signals
  local outcome="success"
  local reward=1.0
  if [[ -f "$log_file" ]]; then
    local recent_errors
    recent_errors="$(tail -20 "$log_file" 2>/dev/null | grep -ci 'ERROR\|FAIL\|fatal\|panic' || echo "0")"
    local recent_warnings
    recent_warnings="$(tail -20 "$log_file" 2>/dev/null | grep -ci 'WARNING\|WARN\|retry' || echo "0")"
    if (( recent_errors > 2 )); then
      outcome="failure"
      reward=-0.5
    elif (( recent_errors > 0 || recent_warnings > 2 )); then
      outcome="partial"
      reward=0.5
    fi
  fi

  # Record each agent usage
  local recorded=0
  for i in "${!agents_used[@]}"; do
    local agent="${agents_used[$i]}"
    local task_sig="${task_sigs[$i]}"
    sqlite3 "$DB_PATH" "INSERT INTO agent_usage_log (session_id, task_signature, agent_id, outcome, reward)
      VALUES ('$(escape_sql "$session_id")', '$(escape_sql "$task_sig")', '$(escape_sql "$agent")', '$(escape_sql "$outcome")', $reward);" 2>/dev/null || true
    (( recorded++ )) || true
  done

  if (( recorded > 0 )); then
    echo "[omc] Agent usage tracked: ${recorded} agents (outcome: $outcome, reward: $reward)" >&2
  fi
}

track_agent_usage

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
# Garbage Collection: proposals.json aged-out entries
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# Consolidate
# ---------------------------------------------------------------------------
if [[ -f "$CONSOLIDATE_SCRIPT" ]]; then
  bash "$CONSOLIDATE_SCRIPT" 2>/dev/null
fi
