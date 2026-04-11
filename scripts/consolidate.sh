#!/usr/bin/env bash
# consolidate.sh — Periodic memory consolidation for oh-my-copilot.
# Ported from consolidate.ps1
#
# Usage:
#   ./consolidate.sh [DB_PATH [LEARN_PATH]]
#
# Arguments:
#   DB_PATH     (optional) Path to the SQLite memory DB.
#               Default: $STATE_ROOT/omc-memory.db
#   LEARN_PATH  (optional) Path to the LEARNINGS.md file.
#               Default: $STATE_ROOT/LEARNINGS.md
#
# NOTE: set -e is intentionally omitted so that non-fatal errors (e.g.
#       a missing LEARNINGS.md) do not abort the entire consolidation run.

set -uo pipefail

# ── Paths ─────────────────────────────────────────────────────────────────────

STATE_ROOT="$HOME/.copilot/oh-my-copilot"
DB_PATH="${1:-$STATE_ROOT/omc-memory.db}"
LEARN_PATH="${2:-$STATE_ROOT/LEARNINGS.md}"

# ── Dependency check ─────────────────────────────────────────────────────────

if ! command -v sqlite3 &>/dev/null; then
  echo "[omc] ERROR: sqlite3 is required but not installed. Install sqlite3 to enable memory consolidation." >&2
  exit 1
fi

# ── DB existence check ────────────────────────────────────────────────────────
# If the DB is missing, attempt to create it via init-memory.sh first.
# If initialization fails for any reason, skip consolidation gracefully.

if [[ ! -f "$DB_PATH" ]]; then
    echo "[omc] Memory DB not found, skipping consolidation"
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    INIT_SCRIPT="$SCRIPT_DIR/init-memory.sh"
    if [[ -x "$INIT_SCRIPT" ]]; then
        echo "[omc] Attempting DB initialization via init-memory.sh …"
        if ! "$INIT_SCRIPT" "$DB_PATH"; then
            echo "[omc] init-memory.sh failed — aborting consolidation." >&2
            exit 0
        fi
    else
        exit 0
    fi
fi

# ── Helper: escape SQL string values (single and double quotes) ───────────────

escape_sql() { local v="$1"; v="${v//\'/\'\'}"; v="${v//\"/\"\"}"; printf '%s' "$v"; }

# ── Helper: run a SQL statement, ignore errors ────────────────────────────────

run_sql() {
    sqlite3 "$DB_PATH" "$1" 2>/dev/null || true
}

# ── Step 1: Refresh last_accessed for stale entries ──────────────────────────
# Any memory not touched in the last day gets its timestamp bumped and its
# access counter incremented (keeps the priority score from stagnating).

echo "[omc] Step 1/6 — Refreshing stale access timestamps …"
run_sql "UPDATE semantic_memory
         SET last_accessed = CURRENT_TIMESTAMP,
             access_count  = access_count + 1
         WHERE last_accessed < datetime('now', '-1 day');"

# ── Step 2: Priority-decay eviction ──────────────────────────────────────────
# Remove entries that are both old (>30 days) and have fallen below the
# minimum priority score threshold.
#
# Priority score formula:
#   (base_importance × access_count) / (days_since_last_access + 1)

# Priority threshold: entries with score < 0.01 are candidates for eviction.
# Score = (base_importance * access_count) / (days_since_last_access + 1)
# A score of 0.01 means: an entry accessed once, with base importance 1.0, not accessed in ~99 days.
_sm_count_before=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM semantic_memory;" 2>/dev/null || echo "0")
echo "[omc] Step 2/6 — Running priority-decay eviction …"
run_sql "DELETE FROM semantic_memory
         WHERE (base_importance * access_count)
                 / (CAST(julianday('now') - julianday(last_accessed) AS REAL) + 1) < 0.01
           AND creation_time < datetime('now', '-30 days');"
_sm_count_after=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM semantic_memory;" 2>/dev/null || echo "0")
_sm_evicted=$(( _sm_count_before - _sm_count_after ))

# ── Step 3: Ingest new learnings from LEARNINGS.md ───────────────────────────
# Read the last 10 lines that start with '[' from LEARNINGS.md and insert
# them as new semantic_memory rows (low-signal lines are skipped).

echo "[omc] Step 3/6 — Ingesting new learnings from LEARNINGS.md …"

if [[ -f "$LEARN_PATH" ]]; then
    # Collect the last 10 lines that begin with '['.
    mapfile -t candidates < <(grep '^\[' "$LEARN_PATH" 2>/dev/null | tail -n 10)

    inserted=0
    skipped=0

    for line in "${candidates[@]}"; do
        line="${line:-}"
        # ── Low-signal filter ─────────────────────────────────────────────
        # Skip lines that are too short to carry useful information, or that
        # contain boilerplate "no changes" messages.
        if (( ${#line} < 30 )); then
            (( skipped++ )) || true
            continue
        fi
        if echo "$line" | grep -qi "No agent changes"; then
            (( skipped++ )) || true
            continue
        fi

        # ── Category detection (first match wins) ─────────────────────────
        category="general"
        if echo "$line" | grep -qi "agent";   then category="agent";   fi
        if echo "$line" | grep -qi "error";   then category="error";   fi
        if echo "$line" | grep -qi "pattern"; then category="pattern"; fi
        if echo "$line" | grep -qi "tool";    then category="tool";    fi

        # ── Token weight (capped at 100) ──────────────────────────────────
        token_weight=$(( ${#line} / 10 ))
        (( token_weight > 100 )) && token_weight=100

        # ── SQL injection prevention: escape single and double quotes ────────
        safe_line="$(escape_sql "$line")"

        run_sql "INSERT OR IGNORE INTO semantic_memory
                     (fact_content, category, token_weight)
                 VALUES ('${safe_line}', '${category}', ${token_weight});"
        (( inserted++ )) || true
    done

    echo "[omc]   Learnings ingested: ${inserted}, skipped (low-signal): ${skipped}"
else
    echo "[omc]   LEARNINGS.md not found at ${LEARN_PATH} — skipping ingest."
fi

# ── Step 4: Top-3 memory report ───────────────────────────────────────────────

echo "[omc] Step 4/6 — Top-3 memories by priority score:"
sqlite3 -column -header "$DB_PATH" \
    "SELECT fact_content,
            ROUND(
                (base_importance * access_count)
                  / (CAST(julianday('now') - julianday(last_accessed) AS REAL) + 1),
                3
            ) AS score
     FROM   semantic_memory
     ORDER  BY score DESC
     LIMIT  3;" 2>/dev/null || echo "[omc]   (no memories yet)"

# ── Summary: row counts per table ─────────────────────────────────────────────

echo ""
echo "[omc] ── Table row counts ───────────────────────────────────────────────"
for tbl in semantic_memory meta_policy_rules agent_q_table; do
    count="$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM ${tbl};" 2>/dev/null || echo '?')"
    printf "[omc]   %-25s %s rows\n" "${tbl}" "${count}"
done
echo "[omc] ─────────────────────────────────────────────────────────────────"

# ── Step 5: Garbage Collection ────────────────────────────────────────────────
# Lightweight cleanup of aged-out / expired rows across tables.

echo "[omc] Step 5/6 — Garbage collection …"

# 5a. improvement_candidates: remove records older than 90 days.
# improvement_candidates has no workflow 'status' column — clean purely by age.
# The corresponding proposals.json entries are cleaned separately in session-end.sh.
gc_improvement=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM improvement_candidates WHERE created_at < datetime('now', '-90 days');" 2>/dev/null || echo "0")
run_sql "DELETE FROM improvement_candidates WHERE created_at < datetime('now', '-90 days');"
echo "[omc]   improvement_candidates: ${gc_improvement} aged-out records removed (>90 days)" >&2

# 5b. semantic_memory: log how many entries Step 2 evicted (no additional DELETE).
echo "[omc]   semantic_memory: ${_sm_evicted} entries evicted by priority-decay (Step 2)" >&2

# 5c. permission_cache: remove entries past their expiration time.
run_sql "CREATE TABLE IF NOT EXISTS permission_cache (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    cache_key TEXT NOT NULL,
    cache_value TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    expires_at DATETIME NOT NULL
);"
gc_permission=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM permission_cache WHERE expires_at < datetime('now');" 2>/dev/null || echo "0")
run_sql "DELETE FROM permission_cache WHERE expires_at < datetime('now');"
echo "[omc]   permission_cache: ${gc_permission} expired entries removed" >&2

# ── Step 6: Q-Learning agent_q_table update ──────────────────────────────────
# Apply Q-Learning update from recorded agent usage:
#   Q(s,a) ← Q(s,a) + α(r - Q(s,a))   where α = 0.1
#
# Agent usage records are written by session-end.sh into agent_usage_log.
# Each record contains (task_signature, agent_id, reward).
# After processing, records are marked as processed to avoid double-counting.

echo "[omc] Step 6/6 — Q-Learning agent_q_table update …"

# Ensure agent_usage_log table has a processed flag
run_sql "ALTER TABLE agent_usage_log ADD COLUMN processed INTEGER DEFAULT 0;" 2>/dev/null || true

# Count unprocessed records
q_unprocessed=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM agent_usage_log WHERE processed = 0;" 2>/dev/null || echo "0")

if (( q_unprocessed > 0 )); then
  # Process each unprocessed usage record
  # Aggregate: for each (task_signature, agent_id), compute average reward from unprocessed records
  q_updated=0
  while IFS='|' read -r task_sig agent reward_avg usage_count; do
    [[ -z "$task_sig" || -z "$agent" ]] && continue

    # Get current Q-value (default 0.5 for unseen pairs)
    current_q=$(sqlite3 "$DB_PATH" "SELECT q_value FROM agent_q_table WHERE task_signature='$(escape_sql "$task_sig")' AND agent_id='$(escape_sql "$agent")';" 2>/dev/null || echo "")

    if [[ -z "$current_q" ]]; then
      # New task-agent pair: initialize with the reward as starting Q-value
      current_q="0.5"
      run_sql "INSERT OR IGNORE INTO agent_q_table (task_signature, agent_id, q_value, trials, last_reward, last_updated)
        VALUES ('$(escape_sql "$task_sig")', '$(escape_sql "$agent")', $current_q, 0, 0.0, datetime('now'));"
    fi

    # Q-Learning update: Q(s,a) ← Q(s,a) + α(r - Q(s,a))
    # α = 0.1 (learning rate)
    # r = average reward from this batch of usage records
    alpha=0.1
    # Use awk for floating-point arithmetic (bash doesn't support floats)
    new_q=$(awk "BEGIN { printf \"%.4f\", $current_q + $alpha * ($reward_avg - $current_q) }")

    # Clamp Q-value to [-1.0, 2.0] range to prevent runaway values
    new_q=$(awk "BEGIN { v = $new_q; if (v < -1.0) v = -1.0; if (v > 2.0) v = 2.0; printf \"%.4f\", v }")

    run_sql "UPDATE agent_q_table
      SET q_value = $new_q,
          trials = trials + $usage_count,
          last_reward = $reward_avg,
          last_updated = datetime('now')
      WHERE task_signature = '$(escape_sql "$task_sig")' AND agent_id = '$(escape_sql "$agent")';"

    (( q_updated++ )) || true
  done < <(sqlite3 "$DB_PATH" "SELECT task_signature, agent_id, AVG(reward), COUNT(*) FROM agent_usage_log WHERE processed = 0 GROUP BY task_signature, agent_id;" 2>/dev/null)

  # Mark all as processed
  run_sql "UPDATE agent_usage_log SET processed = 1 WHERE processed = 0;"

  echo "[omc]   Q-Learning: ${q_updated} agent-task pairs updated from ${q_unprocessed} usage records (α=0.1)" >&2
else
  echo "[omc]   Q-Learning: no new agent usage records to process" >&2
fi

# Report current Q-table state
echo "[omc]   Current Q-table top entries:"
sqlite3 -column -header "$DB_PATH" \
  "SELECT task_signature, agent_id, ROUND(q_value, 3) AS q_val, trials
   FROM agent_q_table ORDER BY q_value DESC LIMIT 5;" 2>/dev/null || true

echo "[omc] Consolidation complete."
