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

# ── Dependency check (silent) ─────────────────────────────────────────────────

if ! command -v sqlite3 &>/dev/null; then
    exit 0
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

# ── Helper: run a SQL statement, ignore errors ────────────────────────────────

run_sql() {
    sqlite3 "$DB_PATH" "$1" 2>/dev/null || true
}

# ── Step 1: Refresh last_accessed for stale entries ──────────────────────────
# Any memory not touched in the last day gets its timestamp bumped and its
# access counter incremented (keeps the priority score from stagnating).

echo "[omc] Step 1/4 — Refreshing stale access timestamps …"
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

echo "[omc] Step 2/4 — Running priority-decay eviction …"
run_sql "DELETE FROM semantic_memory
         WHERE (base_importance * access_count)
                 / (CAST(julianday('now') - julianday(last_accessed) AS REAL) + 1) < 0.01
           AND creation_time < datetime('now', '-30 days');"

# ── Step 3: Ingest new learnings from LEARNINGS.md ───────────────────────────
# Read the last 10 lines that start with '[' from LEARNINGS.md and insert
# them as new semantic_memory rows (low-signal lines are skipped).

echo "[omc] Step 3/4 — Ingesting new learnings from LEARNINGS.md …"

if [[ -f "$LEARN_PATH" ]]; then
    # Collect the last 10 lines that begin with '['.
    mapfile -t candidates < <(grep '^\[' "$LEARN_PATH" 2>/dev/null | tail -n 10)

    inserted=0
    skipped=0

    for line in "${candidates[@]}"; do
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

        # ── SQL injection prevention: escape single quotes ─────────────────
        safe_line="${line//\'/\'\'}"

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

echo "[omc] Step 4/4 — Top-3 memories by priority score:"
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
echo "[omc] Consolidation complete."
