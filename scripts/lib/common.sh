#!/usr/bin/env bash
# common.sh — shared variables, error trap, hash_content, sql_escape
set -uo pipefail

# ---------------------------------------------------------------------------
# Error handling
# ---------------------------------------------------------------------------
on_error() {
  echo "[omc] session-end error on line $1" >&2
}
trap 'on_error $LINENO' ERR

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(dirname "$SCRIPT_DIR")"
COPILOT_ROOT="${HOME}/.copilot"
STATE_ROOT="${HOME}/.copilot/oh-my-copilot"
DB_PATH="${STATE_ROOT}/omc-memory.db"
LEARN_PATH="${STATE_ROOT}/LEARNINGS.md"
PROPOSALS_PATH="${STATE_ROOT}/proposals.json"
LOG_PATH="${COPILOT_ROOT}/session.log"
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
TIMESTAMP_ISO="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date '+%Y-%m-%d %H:%M:%S')"
CONSOLIDATE_SCRIPT="${SCRIPT_DIR}/consolidate.sh"

# ---------------------------------------------------------------------------
# Helper: SQL escape
# ---------------------------------------------------------------------------
sql_escape() {
  local value="${1-}"
  value="${value//\'/\'\'}"
  value="${value//\"/\"\"}"
  printf '%s' "$value"
}

# ---------------------------------------------------------------------------
# Helper: Content hashing for deduplication
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

# ---------------------------------------------------------------------------
# Helper: Ensure directories and files exist
# ---------------------------------------------------------------------------
ensure_state_directories() {
  mkdir -p "$STATE_ROOT"
  mkdir -p "$COPILOT_ROOT"
}

ensure_learnings_file() {
  if [[ ! -f "$LEARN_PATH" ]]; then
    touch "$LEARN_PATH"
  fi
}

log_session_end() {
  echo "[$TIMESTAMP] SESSION_END cwd=$(pwd)" >> "$LOG_PATH"
}
