#!/usr/bin/env bash
# status-line.sh — omc status line for Copilot CLI statusLine.command
# Outputs a single line with active mode, memory stats, and pending proposals.
#
# USAGE:
#   Add to ~/.copilot/config.json:
#   {
#     "statusLine": {
#       "command": "~/.copilot/installed-plugins/_direct/Lee-SiHyeon--oh-my-copilot/scripts/status-line.sh"
#     }
#   }
#
# OUTPUT FORMAT:
#   🧠 47 facts | 📋 3 pending | 🔄 ultrawork R2/5
#   🧠 0 facts | 📋 0 pending | 💤 idle

set -uo pipefail

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(dirname "$SCRIPT_DIR")"
export PLUGIN_ROOT
STATE_ROOT="${HOME}/.copilot/oh-my-copilot"
DB_PATH="${STATE_ROOT}/omc-memory.db"
# State file locations to check (both oh-my-claudecode and oh-my-copilot paths)
OMC_STATE_DIR="${HOME}/.copilot/installed-plugins/omc/oh-my-claudecode/.omc/state"
MODES=("ultrawork" "ralph" "autopilot" "ultraqa" "team" "ralplan" "omc-teams" "deep-interview")

# ---------------------------------------------------------------------------
# 1. Memory stats — single SQLite query
# ---------------------------------------------------------------------------
fact_count=""
pending_count=""

if command -v sqlite3 &>/dev/null && [[ -f "$DB_PATH" ]]; then
  IFS='|' read -r fact_count pending_count < <(
    sqlite3 "$DB_PATH" "SELECT
      (SELECT COUNT(*) FROM semantic_memory),
      (SELECT COUNT(*) FROM improvement_candidates WHERE status_snapshot NOT LIKE '%merged%');" 2>/dev/null
  )
fi

# Graceful defaults: "?" if sqlite3 missing, "0" if DB missing or query failed
if ! command -v sqlite3 &>/dev/null; then
  fact_count="?"
  pending_count="?"
else
  fact_count="${fact_count:-0}"
  pending_count="${pending_count:-0}"
fi

# ---------------------------------------------------------------------------
# 2. Active mode detection — file existence + JSON parse (no SQLite)
# ---------------------------------------------------------------------------
active_mode=""
active_detail=""

for mode in "${MODES[@]}"; do
  state_file="${OMC_STATE_DIR}/${mode}-state.json"
  # Also check session-specific paths
  if [[ ! -f "$state_file" ]]; then
    # Try to find in session directories (fast: -print -quit stops at first match)
    state_file="$(find "${OMC_STATE_DIR}/sessions" -name "${mode}-state.json" -newer /tmp -print -quit 2>/dev/null)"
  fi
  if [[ -n "$state_file" && -f "$state_file" ]]; then
    # Parse JSON for active status
    is_active="$(grep -o '"active"[[:space:]]*:[[:space:]]*true' "$state_file" 2>/dev/null)"
    if [[ -n "$is_active" ]]; then
      active_mode="$mode"
      # Try to get iteration info
      iteration="$(grep -o '"iteration"[[:space:]]*:[[:space:]]*[0-9]*' "$state_file" | grep -o '[0-9]*$' 2>/dev/null)"
      max_iter="$(grep -o '"max_iterations"[[:space:]]*:[[:space:]]*[0-9]*' "$state_file" | grep -o '[0-9]*$' 2>/dev/null)"
      if [[ -n "$iteration" && -n "$max_iter" ]]; then
        active_detail="R${iteration}/${max_iter}"
      elif [[ -n "$iteration" ]]; then
        active_detail="R${iteration}"
      fi
      break
    fi
  fi
done

# ---------------------------------------------------------------------------
# 3. Last learning time — quick file stat
# ---------------------------------------------------------------------------
last_learn=""
learn_file="${STATE_ROOT}/LEARNINGS.md"

if [[ -f "$learn_file" ]] && [[ -s "$learn_file" ]]; then
  # Get modification time in human-readable relative format
  mod_epoch="$(stat -c%Y "$learn_file" 2>/dev/null || stat -f%m "$learn_file" 2>/dev/null)"
  if [[ -n "$mod_epoch" ]]; then
    now_epoch="$(date +%s)"
    diff_sec=$(( now_epoch - mod_epoch ))
    if (( diff_sec < 60 )); then
      last_learn="${diff_sec}s ago"
    elif (( diff_sec < 3600 )); then
      last_learn="$(( diff_sec / 60 ))m ago"
    elif (( diff_sec < 86400 )); then
      last_learn="$(( diff_sec / 3600 ))h ago"
    else
      last_learn="$(( diff_sec / 86400 ))d ago"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# 4. Output assembly — single line to stdout
# ---------------------------------------------------------------------------
parts=()
parts+=("🧠 ${fact_count} facts")
parts+=("📋 ${pending_count} pending")

if [[ -n "$last_learn" ]]; then
  parts+=("📚 ${last_learn}")
fi

if [[ -n "$active_mode" ]]; then
  if [[ -n "$active_detail" ]]; then
    parts+=("🔄 ${active_mode} ${active_detail}")
  else
    parts+=("🔄 ${active_mode}")
  fi
else
  parts+=("💤 idle")
fi

# Join with pipe separator
IFS='|'; echo "${parts[*]}" | sed 's/|/ | /g'
