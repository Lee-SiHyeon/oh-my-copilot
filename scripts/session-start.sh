#!/usr/bin/env bash
# session-start.sh — omc session initialization (ported from session-start.ps1)
set -uo pipefail

# Dependency check
# shellcheck disable=SC2043  # Single-dep loop retained for future extensibility
for dep in sqlite3; do
  if ! command -v "$dep" &>/dev/null; then
    echo "[omc] WARNING: '$dep' is not installed. Some features may be unavailable." >&2
  fi
done

# WSL: check pwsh availability (used by PowerShell companion scripts)
if [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qi 'microsoft' /proc/version 2>/dev/null; then
  if ! command -v pwsh &>/dev/null; then
    echo "[omc] WSL detected. Optional: install PowerShell Core (pwsh) for full feature support." >&2
    echo "[omc]   Install: https://aka.ms/install-powershell" >&2
  fi
fi

# ---------------------------------------------------------------------------
# Experimental mode advisory (one-time per install)
# ---------------------------------------------------------------------------
_omc_exp_flag="${HOME}/.copilot/oh-my-copilot/.experimental-advised"
if [ ! -f "$_omc_exp_flag" ]; then
  # Check if experimental is already enabled in config.json
  _copilot_cfg="${HOME}/.copilot/config.json"
  _exp_enabled=false
  if [ -f "$_copilot_cfg" ] && command -v jq &>/dev/null; then
    _exp_enabled="$(jq -r '.experimental // false' "$_copilot_cfg" 2>/dev/null || echo false)"
  fi
  if [ "$_exp_enabled" != "true" ]; then
    echo "[omc] ⚡ Tip: Run '/experimental on' to unlock full oh-my-copilot capabilities."
    echo "[omc]    (multi-turn agents, session store, structured forms, status line)"
  fi
  # Create flag so this message shows only once
  mkdir -p "$(dirname "$_omc_exp_flag")"
  touch "$_omc_exp_flag"
fi

# ---------------------------------------------------------------------------
# Background Session Recovery
# ---------------------------------------------------------------------------
# Check for active ralph/ultrawork states from previous sessions
if [ "$_exp_enabled" = "true" ]; then
    _ralph_state="${HOME}/.copilot/oh-my-copilot/ralph-state.json"
    if [ -f "$_ralph_state" ] && command -v jq >/dev/null 2>&1; then
        _ralph_active=$(jq -r '.active // false' "$_ralph_state" 2>/dev/null)
        if [ "$_ralph_active" = "true" ]; then
            _ralph_iter=$(jq -r '.iteration // 0' "$_ralph_state" 2>/dev/null)
            _ralph_task=$(jq -r '.task // "unknown"' "$_ralph_state" 2>/dev/null)
            echo "⏸️  Found paused ralph-loop: iteration $_ralph_iter — \"$_ralph_task\""
            echo "   Use /ralph to resume or /cancel to discard"
        fi
    fi
fi

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

# Log rotation: keep log under 1MB, rotate to .1 backup
LOG_FILE="${STATE_ROOT}/session.log"
if [ -f "$LOG_FILE" ] && [ "$(stat -c%s "$LOG_FILE" 2>/dev/null || stat -f%z "$LOG_FILE" 2>/dev/null || echo 0)" -gt 1048576 ]; then
  mv "$LOG_FILE" "${LOG_FILE}.1"
  echo "[omc] Log rotated: ${LOG_FILE}.1" >&2
fi
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

# ---------------------------------------------------------------------------
# STATUS_LINE: Real-time status display for Copilot CLI
# ---------------------------------------------------------------------------
# To enable the omc status line, add to ~/.copilot/config.json:
#
#   {
#     "statusLine": {
#       "command": "~/.copilot/installed-plugins/_direct/Lee-SiHyeon--oh-my-copilot/scripts/status-line.sh"
#     }
#   }
#
# The status line shows: memory facts | pending proposals | active mode
# Example: 🧠 47 facts | 📋 3 pending | 🔄 ultrawork R2/5
# ---------------------------------------------------------------------------
