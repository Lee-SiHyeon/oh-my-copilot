#!/usr/bin/env bash
# 공통 헬퍼 - 모든 test suite에서 source

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPTS_DIR="$REPO_ROOT/scripts"

# bats-assert, bats-file 로드
load "$REPO_ROOT/tests/test_helper/bats-support/load"
load "$REPO_ROOT/tests/test_helper/bats-assert/load"
load "$REPO_ROOT/tests/test_helper/bats-file/load"
