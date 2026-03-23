#!/usr/bin/env bash
# 로컬에서 전체 테스트 실행 스크립트
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BATS="$REPO_ROOT/tests/bats/bin/bats"

if [[ ! -f "$BATS" ]]; then
  echo "❌ bats submodule not found. Run: git submodule update --init --recursive"
  exit 1
fi

echo "🧪 Running omc TDD suite..."
"$BATS" --recursive "$REPO_ROOT/tests/unit" \
  --timing \
  --print-output-on-failure \
  "${@}"
