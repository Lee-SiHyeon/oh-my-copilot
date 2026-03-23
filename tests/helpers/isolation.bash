#!/usr/bin/env bash
# 격리 환경 설정 헬퍼

ISOLATED_HOME=""

setup_isolation() {
  ISOLATED_HOME="$(mktemp -d)"
  export HOME="$ISOLATED_HOME"
  export XDG_CONFIG_HOME="$ISOLATED_HOME/.config"
  export PATH="${PATH//:\/home\/worker\/.local\/bin/}"  # nlm 등 격리
}

teardown_isolation() {
  [[ -n "$ISOLATED_HOME" && -d "$ISOLATED_HOME" ]] && rm -rf "$ISOLATED_HOME"
}

create_test_db() {
  local db_path="$1"
  sqlite3 "$db_path" "
    CREATE TABLE IF NOT EXISTS meta_policy_rules (
      id INTEGER PRIMARY KEY,
      rule_name TEXT,
      pattern TEXT,
      action TEXT,
      severity TEXT DEFAULT 'HIGH'
    );
    CREATE TABLE IF NOT EXISTS semantic_memory (
      id INTEGER PRIMARY KEY,
      content TEXT,
      embedding TEXT,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );
    CREATE TABLE IF NOT EXISTS agent_q_table (
      id INTEGER PRIMARY KEY,
      state TEXT,
      action TEXT,
      q_value REAL DEFAULT 0.0
    );
  "
}
