#!/usr/bin/env bash
# git-status-parser.sh — normalize_status_path, git status parsing, path classification
set -uo pipefail

# ---------------------------------------------------------------------------
# Helper: shared-path filter and git status parsing
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

parse_git_status() {
  local plugin_root="$1"
  local -n status_lines_ref=$2
  local -n shared_paths_ref=$3
  local -n ignored_paths_ref=$4
  local -n readme_sync_paths_ref=$5
  local -n readme_changed_ref=$6

  cd "$plugin_root" || { echo "[omc] ERROR: Failed to cd to plugin_root='$plugin_root'" >&2; return 1; }

  mapfile -t status_lines_ref < <(git status --porcelain --untracked-files=all 2>/dev/null)

  shared_paths_ref=()
  ignored_paths_ref=()
  readme_sync_paths_ref=()
  readme_changed_ref=false

  for line in "${status_lines_ref[@]}"; do
    raw_path="$(normalize_status_path "$line")"
    [[ -n "$raw_path" ]] || continue

    if is_shared_path "$raw_path"; then
      shared_paths_ref+=("$raw_path")
    else
      ignored_paths_ref+=("$raw_path")
    fi

    if [[ "$raw_path" == "README.md" ]]; then
      readme_changed_ref=true
    fi

    if is_readme_sync_guard_path "$raw_path"; then
      readme_sync_paths_ref+=("$raw_path")
    fi
  done
}
