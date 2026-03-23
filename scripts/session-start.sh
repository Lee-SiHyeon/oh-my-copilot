#!/usr/bin/env bash
# session-start.sh — omc session initialization (ported from session-start.ps1)
set -uo pipefail

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(dirname "$SCRIPT_DIR")"
STATE_ROOT="${HOME}/.copilot/oh-my-copilot"
COPILOT_ROOT="${HOME}/.copilot"
DB_PATH="${STATE_ROOT}/omc-memory.db"
LEARN_PATH="${STATE_ROOT}/LEARNINGS.md"
LOG_PATH="${COPILOT_ROOT}/session.log"
AGENTS_DIR="${COPILOT_ROOT}/agents"
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"

# ---------------------------------------------------------------------------
# Ensure directories exist
# ---------------------------------------------------------------------------
mkdir -p "$STATE_ROOT"
mkdir -p "$COPILOT_ROOT"

# ---------------------------------------------------------------------------
# Database bootstrap
# ---------------------------------------------------------------------------
if [[ ! -f "$DB_PATH" ]]; then
  LEGACY_DB="${PLUGIN_ROOT}/omc-memory.db"
  if [[ -f "$LEGACY_DB" ]]; then
    cp "$LEGACY_DB" "$DB_PATH"
  else
    INIT_SCRIPT="${SCRIPT_DIR}/init-memory.sh"
    if [[ -f "$INIT_SCRIPT" ]]; then
      bash "$INIT_SCRIPT"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Ensure LEARNINGS.md exists
# ---------------------------------------------------------------------------
if [[ ! -f "$LEARN_PATH" ]]; then
  touch "$LEARN_PATH"
fi

# ---------------------------------------------------------------------------
# Log session start
# ---------------------------------------------------------------------------
echo "[$TIMESTAMP] SESSION_START cwd=$(pwd)" >> "$LOG_PATH"

# ---------------------------------------------------------------------------
# Top 5 memories (requires sqlite3 + DB)
# ---------------------------------------------------------------------------
if command -v sqlite3 &>/dev/null && [[ -f "$DB_PATH" ]]; then
  mapfile -t memories < <(
    sqlite3 "$DB_PATH" \
      "SELECT fact_content FROM semantic_memory \
       ORDER BY (base_importance * access_count) / \
                (CAST(julianday('now') - julianday(last_accessed) AS REAL) + 1) DESC \
       LIMIT 5;" 2>/dev/null
  )
  if [[ ${#memories[@]} -gt 0 ]]; then
    joined="$(printf '%s' "${memories[0]}"; printf ' | %s' "${memories[@]:1}")"
    echo "[omc] Top memories: ${joined}"
  fi
fi

# ---------------------------------------------------------------------------
# Last 3 lines of LEARNINGS.md
# ---------------------------------------------------------------------------
if [[ -f "$LEARN_PATH" ]]; then
  mapfile -t last_lines < <(tail -n 3 "$LEARN_PATH" 2>/dev/null)
  # Filter out empty lines
  filtered=()
  for line in "${last_lines[@]}"; do
    [[ -n "$line" ]] && filtered+=("$line")
  done
  if [[ ${#filtered[@]} -gt 0 ]]; then
    joined="$(printf '%s' "${filtered[0]}"; printf ' | %s' "${filtered[@]:1}")"
    echo "[omc] Last learnings: ${joined}"
  fi
fi

# ---------------------------------------------------------------------------
# Personal agents
# ---------------------------------------------------------------------------
agent_names=()
if [[ -d "$AGENTS_DIR" ]]; then
  while IFS= read -r -d '' agent_file; do
    base="$(basename "$agent_file")"
    # Remove .agent.md → strip .md first, then .agent suffix
    name="${base%.agent.md}"
    agent_names+=("$name")
  done < <(find "$AGENTS_DIR" -maxdepth 1 -name "*.agent.md" -print0 2>/dev/null)
fi

if [[ ${#agent_names[@]} -gt 0 ]]; then
  joined="$(printf '%s' "${agent_names[0]}"; printf ', %s' "${agent_names[@]:1}")"
  echo "[omc] Your personal agents: ${joined}"
else
  echo "[omc] No personal agents yet. Run: /agent oh-my-copilot:personal-advisor"
fi
