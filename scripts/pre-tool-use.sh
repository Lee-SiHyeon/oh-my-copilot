#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(dirname "$SCRIPT_DIR")"
STATE_ROOT="${HOME}/.copilot/oh-my-copilot"
DB_PATH="${STATE_ROOT}/omc-memory.db"

# ---------------------------------------------------------------------------
# JSON 파싱 함수 (jq 우선, fallback python3)
# usage: parse_json "<json_string>" ".fieldName"
# ---------------------------------------------------------------------------
parse_json() {
    local json="$1" field="$2"
    if command -v jq &>/dev/null; then
        echo "$json" | jq -r "$field // empty" 2>/dev/null
    elif command -v python3 &>/dev/null; then
        echo "$json" | python3 -c "
import json, sys
d = json.load(sys.stdin)
# field 형태: .toolName 또는 .toolArgs
key = '${field#.}'.split('.')[0]
val = d.get(key, '')
if isinstance(val, (dict, list)):
    print(json.dumps(val))
else:
    print(val)
" 2>/dev/null
    fi
}

# ---------------------------------------------------------------------------
# JSON 응답 출력 함수
# usage: emit_decision "<decision>" "<reason>"
# ---------------------------------------------------------------------------
emit_decision() {
    local decision="$1" reason="$2"
    if command -v jq &>/dev/null; then
        jq -cn --arg d "$decision" --arg r "$reason" \
            '{permissionDecision:$d,permissionDecisionReason:$r}'
    else
        # reason의 백슬래시·큰따옴표 이스케이프
        local reason_escaped="${reason//\\/\\\\}"
        reason_escaped="${reason_escaped//\"/\\\"}"
        echo "{\"permissionDecision\":\"$decision\",\"permissionDecisionReason\":\"$reason_escaped\"}"
    fi
}

# ---------------------------------------------------------------------------
# 1. stdin에서 JSON 읽기
# ---------------------------------------------------------------------------
INPUT="$(cat -)"

# stdin이 비어있으면 조용히 종료
if [[ -z "$INPUT" ]]; then
    exit 0
fi

# ---------------------------------------------------------------------------
# 2. JSON 파싱: toolName / toolArgs 추출
# ---------------------------------------------------------------------------
TOOL_NAME="$(parse_json "$INPUT" ".toolName")"
TOOL_ARGS_RAW="$(parse_json "$INPUT" ".toolArgs")"

# toolArgs가 dict/object인 경우 JSON 문자열로 직렬화된 상태로 사용
TOOL_ARGS="${TOOL_ARGS_RAW}"

# ---------------------------------------------------------------------------
# 3. DB 초기화 (DB 없고 init-memory.sh 있으면 자동 시도)
# ---------------------------------------------------------------------------
if [[ ! -f "$DB_PATH" ]] && [[ -f "${SCRIPT_DIR}/init-memory.sh" ]]; then
    bash "${SCRIPT_DIR}/init-memory.sh" &>/dev/null || true
fi

# ---------------------------------------------------------------------------
# 4. 위험 패턴 감지 (bash/shell 계열 툴에만 적용)
# ---------------------------------------------------------------------------
is_shell_tool=false
case "${TOOL_NAME,,}" in
    bash|shell|powershell|execute)
        is_shell_tool=true
        ;;
esac

if [[ "$is_shell_tool" == true ]]; then
    # toolArgs를 소문자로 변환해 case-insensitive 매칭
    args_lower="${TOOL_ARGS,,}"

    matched_pattern=""

    # 각 위험 패턴을 순서대로 검사 (먼저 매칭된 패턴으로 보고)
    if [[ "$args_lower" == *"rm -rf"* ]]; then
        matched_pattern="rm -rf"
    elif [[ "$args_lower" == *"rm -r -force"* ]]; then
        matched_pattern="rm -r -force"
    elif [[ "$args_lower" == *"git push --force"* ]]; then
        matched_pattern="git push --force"
    elif [[ "$args_lower" == *"git push -f"* ]]; then
        matched_pattern="git push -f"
    elif [[ "$args_lower" == *"drop table"* ]]; then
        matched_pattern="DROP TABLE"
    elif [[ "$args_lower" == *"delete from"* ]]; then
        matched_pattern="DELETE FROM"
    elif [[ "$args_lower" == *"format-volume"* ]]; then
        matched_pattern="format-volume"
    elif [[ "$args_lower" == *"del /f /s"* ]]; then
        matched_pattern="del /f /s"
    elif [[ "$args_lower" == *"rd /s /q"* ]]; then
        matched_pattern="rd /s /q"
    fi

    if [[ -n "$matched_pattern" ]]; then
        emit_decision "ask" "Dangerous operation detected: ${matched_pattern}"
        exit 0
    fi
fi

# ---------------------------------------------------------------------------
# 5. Agent policy 체크
#    toolName이 task/delegate/subagent/modelselect 계열이고
#    toolArgs에 opus 관련 키워드 포함 시 거부 요청
# ---------------------------------------------------------------------------
is_agent_tool=false
case "${TOOL_NAME,,}" in
    task|delegate|subagent|modelselect|model_select|agent)
        is_agent_tool=true
        ;;
esac

if [[ "$is_agent_tool" == true ]]; then
    args_lower="${TOOL_ARGS,,}"
    if [[ "$args_lower" == *"claude-opus"* ]] || [[ "$args_lower" == *"opus"* ]]; then
        emit_decision "ask" "Policy check (agent): MUST refuse and use Sonnet instead"
        exit 0
    fi
fi

# ---------------------------------------------------------------------------
# 6. SQLite meta_policy_rules 조회
# ---------------------------------------------------------------------------
# domain 결정 로직
domain=""

args_lower_for_domain="${TOOL_ARGS,,}"

if [[ "$args_lower_for_domain" == *"git push --force"* ]] || \
   [[ "$args_lower_for_domain" == *"git push -f"* ]]; then
    domain="git"
elif [[ "$is_agent_tool" == true ]]; then
    domain="agent"
elif [[ "$args_lower_for_domain" == *"rm -rf"* ]] || \
     [[ "$args_lower_for_domain" == *"rm -r -force"* ]] || \
     [[ "$args_lower_for_domain" == *"del /f /s"* ]] || \
     [[ "$args_lower_for_domain" == *"rd /s /q"* ]]; then
    domain="file_io"
fi

# domain이 결정됐고, sqlite3과 DB가 모두 존재하는 경우에만 조회
if [[ -n "$domain" ]] && command -v sqlite3 &>/dev/null && [[ -f "$DB_PATH" ]]; then
    rules_output="$(sqlite3 "$DB_PATH" \
        "SELECT action_constraint FROM meta_policy_rules \
         WHERE task_domain='${domain}' AND is_active=1;" 2>/dev/null || true)"

    if [[ -n "$rules_output" ]]; then
        # 여러 행을 '; '로 합치기
        rules_joined="$(echo "$rules_output" | paste -sd '; ' -)"
        emit_decision "ask" "Policy check (${domain}): ${rules_joined}"
        exit 0
    fi
fi

# ---------------------------------------------------------------------------
# 7. 아무것도 매칭되지 않으면 조용히 종료
# ---------------------------------------------------------------------------
exit 0
