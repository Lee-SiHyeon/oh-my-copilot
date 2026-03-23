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

# ---------------------------------------------------------------------------
# Auto-learn commit
# ---------------------------------------------------------------------------
if ! command -v git &>/dev/null; then
  echo "[omc] Git not available, skipping auto-learn commit"
else
  cd "$PLUGIN_ROOT"

  # Parse git status into changed paths
  mapfile -t status_lines < <(git status --porcelain --untracked-files=all 2>/dev/null)

  shared_paths=()
  readme_sync_paths=()
  readme_changed=false
  for line in "${status_lines[@]}"; do
    raw_path="$(normalize_status_path "$line")"
    [[ -n "$raw_path" ]] || continue

    if is_shared_path "$raw_path"; then
      shared_paths+=("$raw_path")
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
    # Stage only the filtered shared paths
    git add -- "${shared_paths[@]}"

    # Check whether anything is actually staged
    mapfile -t staged_files < <(git diff --cached --name-only 2>/dev/null)

    if [[ ${#staged_files[@]} -gt 0 ]]; then
      if git commit -m "auto-learn: $TIMESTAMP" --no-verify 2>/dev/null; then
        git push origin main 2>/dev/null || true
        echo "[$TIMESTAMP] auto-learn commit pushed" >> "$LEARN_PATH"
        echo "[omc] Self-improved: committed shared source changes"
      fi
    fi
  else
    echo "[omc] No shared source changes to commit"
  fi
fi

# ---------------------------------------------------------------------------
# Consolidate
# ---------------------------------------------------------------------------
if [[ -f "$CONSOLIDATE_SCRIPT" ]]; then
  bash "$CONSOLIDATE_SCRIPT" 2>/dev/null
fi
