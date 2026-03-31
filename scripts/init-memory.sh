#!/usr/bin/env bash
# init-memory.sh — Initialize the oh-my-copilot SQLite memory database.
# Ported from init-memory.ps1
#
# Usage:
#   ./init-memory.sh [DB_PATH]
#
# Arguments:
#   DB_PATH  (optional) Override the default database file path.
#            Default: $HOME/.copilot/oh-my-copilot/omc-memory.db

set -euo pipefail

# Dependency check
for dep in sqlite3; do
  if ! command -v "$dep" &>/dev/null; then
    echo "[omc] WARNING: '$dep' is not installed. Some features may be unavailable." >&2
  fi
done

# ── Resolve paths ────────────────────────────────────────────────────────────

# Directory that contains THIS script, resolved to an absolute path.
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Default DB location; can be overridden by the first positional argument.
DB_PATH="${1:-$HOME/.copilot/oh-my-copilot/omc-memory.db}"

# ── Dependency check ─────────────────────────────────────────────────────────

if ! command -v sqlite3 &>/dev/null; then
    echo "[omc] ERROR: sqlite3 is not installed or not on PATH." >&2
    echo "[omc]        Install it (e.g. 'sudo apt install sqlite3') and retry." >&2
    exit 1
fi

# ── Legacy DB migration ───────────────────────────────────────────────────────
# If a database exists in the old plugin-root location, migrate it once to the
# new canonical path, then continue so schema upgrades are still applied.

LEGACY_DB="$PLUGIN_ROOT/omc-memory.db"

if [[ "$DB_PATH" != "$LEGACY_DB" && ! -f "$DB_PATH" && -f "$LEGACY_DB" ]]; then
    echo "[omc] Legacy DB detected at: $LEGACY_DB"
    echo "[omc] Migrating → $DB_PATH"
    mkdir -p "$(dirname "$DB_PATH")"
    cp "$LEGACY_DB" "$DB_PATH"
    echo "[omc] Migration complete."
fi

# ── Ensure target directory exists ───────────────────────────────────────────

mkdir -p "$(dirname "$DB_PATH")"

# ── Schema creation ───────────────────────────────────────────────────────────

sqlite3 "$DB_PATH" <<'SQL'
-- ── Tables ──────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS semantic_memory (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    fact_content    TEXT    NOT NULL,
    category        TEXT    DEFAULT 'general',
    token_weight    INTEGER DEFAULT 0,
    base_importance REAL    DEFAULT 1.0,
    access_count    INTEGER DEFAULT 1,
    creation_time   DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_accessed   DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_semantic_memory_priority
  ON semantic_memory (base_importance, access_count, last_accessed);

CREATE TABLE IF NOT EXISTS meta_policy_rules (
    id                   INTEGER PRIMARY KEY AUTOINCREMENT,
    task_domain          TEXT    NOT NULL,
    predicate_condition  TEXT    NOT NULL,
    action_constraint    TEXT    NOT NULL,
    confidence_weight    REAL    DEFAULT 1.0,
    violation_count      INTEGER DEFAULT 0,
    is_active            INTEGER DEFAULT 1,
    created_at           DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS agent_q_table (
    task_signature       TEXT    NOT NULL,
    agent_id             TEXT    NOT NULL,
    q_value              REAL    DEFAULT 0.0,
    trials               INTEGER DEFAULT 0,
    last_reward          REAL    DEFAULT 0.0,
    last_updated         DATETIME DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (task_signature, agent_id)
);

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

CREATE TABLE IF NOT EXISTS permission_cache (
    tool_name    TEXT NOT NULL,
    pattern_hash TEXT NOT NULL,
    decision     TEXT NOT NULL CHECK(decision IN ('allow','deny')),
    risk_level   TEXT DEFAULT 'low',
    created_at   TEXT DEFAULT (datetime('now')),
    expires_at   TEXT DEFAULT (datetime('now', '+7 days')),
    PRIMARY KEY (tool_name, pattern_hash)
);

CREATE TABLE IF NOT EXISTS proposals (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    content_hash    TEXT    UNIQUE NOT NULL,
    type            TEXT    NOT NULL,
    content         TEXT    NOT NULL,
    status          TEXT    DEFAULT 'pending',
    priority        TEXT    DEFAULT 'normal',
    file_path       TEXT,
    suggested_change TEXT,
    created_at      TEXT    DEFAULT (datetime('now')),
    resolved_at     TEXT
);

CREATE INDEX IF NOT EXISTS idx_proposals_status ON proposals (status);
CREATE INDEX IF NOT EXISTS idx_proposals_hash ON proposals (content_hash);

CREATE TABLE IF NOT EXISTS agent_usage_log (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id      TEXT    NOT NULL,
    task_signature  TEXT    NOT NULL,
    agent_id        TEXT    NOT NULL,
    outcome         TEXT    DEFAULT 'unknown',
    reward          REAL    DEFAULT 0.0,
    created_at      TEXT    DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_agent_usage_session ON agent_usage_log (session_id);

-- ── Seed: meta_policy_rules ──────────────────────────────────────────────────

INSERT OR IGNORE INTO meta_policy_rules (id, task_domain, predicate_condition, action_constraint)
VALUES
    (1, 'git',    'force push',           'MUST ask user confirmation before git push --force'),
    (2, 'file_io','recursive delete',     'MUST confirm before rm -rf'),
    (3, 'agent',  'opus model requested', 'MUST refuse and use Sonnet instead'),
    (4, 'agent',  'delegation prompt',    'MUST include all 6 sections, minimum 30 lines'),
    (5, 'nlm',    'new research start',   'MUST import previous research before starting new');

-- ── Seed: agent_q_table ──────────────────────────────────────────────────────

INSERT OR IGNORE INTO agent_q_table (task_signature, agent_id, q_value, trials) VALUES
    ('research',        'nlm-researcher',  1.0, 1),
    ('research',        'librarian',       0.7, 1),
    ('code_complex',    'hephaestus',      1.0, 1),
    ('code_simple',     'sisyphus-junior', 1.0, 1),
    ('planning',        'prometheus',      1.0, 1),
    ('debugging',       'oracle',          1.0, 1),
    ('codebase_search', 'explore',         1.0, 1);
SQL

echo "[omc] Memory DB initialized: $DB_PATH"
