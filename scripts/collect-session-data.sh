#!/usr/bin/env bash
# collect-session-data.sh
# Collects omc session history and outputs a structured JSON report to stdout.
# Consumed by the personal-advisor agent to recommend personalised agents.
#
# Usage:
#   bash scripts/collect-session-data.sh [--depth <days>] [--verbose]
#
# Options:
#   --depth <days>   Look-back window in days (default: 30)
#   --verbose        Emit diagnostic messages to stderr; stdout stays JSON
#
# Outputs:
#   UTF-8 JSON (stdout) conforming to the personal-advisor data contract:
#     analysisDate, sessionCount, topDirectories, completedTodos,
#     agentQTable, dominantDomains, suggestedAgentNames, mcpSignals

set -euo pipefail

DEPTH=30
VERBOSE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --depth) DEPTH="$2"; shift 2 ;;
    --verbose) VERBOSE=1; shift ;;
    *) shift ;;
  esac
done

diag() {
  [[ $VERBOSE -eq 1 ]] && echo "[collect-session-data] $*" >&2 || true
}

COPILOT_ROOT="${HOME}/.copilot"
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
USER_STATE_ROOT="${COPILOT_ROOT}/oh-my-copilot"
SESSION_LOG="${USER_STATE_ROOT}/session.log"
OMC_DB="${USER_STATE_ROOT}/omc-memory.db"
MCP_CONFIG="${COPILOT_ROOT}/mcp.json"

diag "PLUGIN_ROOT=$PLUGIN_ROOT"
diag "USER_STATE_ROOT=$USER_STATE_ROOT"

# python3 is required for session data collection
if ! command -v python3 &>/dev/null; then
  echo "[omc] ERROR: python3 is required by collect-session-data.sh but not found." >&2
  echo "[omc]   Install on WSL/Ubuntu: sudo apt-get install python3" >&2
  echo '{"analysisDate":"","sessionCount":0,"topDirectories":[],"completedTodos":[],"agentQTable":[],"dominantDomains":[],"suggestedAgentNames":[],"mcpSignals":[]}'
  exit 1
fi

python3 - <<PYEOF
import json, os, re, subprocess, sys
from datetime import datetime, timedelta

DEPTH = int("${DEPTH}")
VERBOSE = ${VERBOSE} == 1
SESSION_LOG = "${SESSION_LOG}"
OMC_DB = "${OMC_DB}"
MCP_CONFIG = "${MCP_CONFIG}"
PLUGIN_ROOT = "${PLUGIN_ROOT}"

def diag(msg):
    if VERBOSE:
        print(f"[collect-session-data] {msg}", file=sys.stderr)

# ─── A. sessionCount ──────────────────────────────────────────────────────────
session_count = 0
cutoff = datetime.now() - timedelta(days=DEPTH)
if os.path.isfile(SESSION_LOG):
    try:
        with open(SESSION_LOG, encoding="utf-8", errors="replace") as f:
            for line in f:
                m = re.search(r"(\d{4}-\d{2}-\d{2})", line)
                if m:
                    try:
                        d = datetime.strptime(m.group(1), "%Y-%m-%d")
                        if d >= cutoff:
                            session_count += 1
                    except ValueError:
                        pass
    except Exception as e:
        diag(f"session.log read error: {e}")
diag(f"sessionCount={session_count}")

# ─── B. topDirectories ────────────────────────────────────────────────────────
dir_counts = {}
if os.path.isfile(SESSION_LOG):
    try:
        with open(SESSION_LOG, encoding="utf-8", errors="replace") as f:
            for line in f:
                m = re.search(r"cwd[=:\s]+([^\s,;]+)", line)
                if m:
                    d = m.group(1).rstrip("/")
                    dir_counts[d] = dir_counts.get(d, 0) + 1
    except Exception:
        pass

top_dirs = sorted(dir_counts.items(), key=lambda x: -x[1])[:5]
top_directories = [{"path": p, "count": c} for p, c in top_dirs]
diag(f"topDirectories={len(top_directories)}")

# ─── C. completedTodos ────────────────────────────────────────────────────────
completed_todos = []

def run_sqlite(db, query):
    try:
        r = subprocess.run(
            ["sqlite3", "-json", db, query],
            capture_output=True, text=True, timeout=10
        )
        if r.returncode == 0 and r.stdout.strip():
            return json.loads(r.stdout)
    except Exception as e:
        diag(f"sqlite3 error: {e}")
    return []

if os.path.isfile(OMC_DB):
    rows = run_sqlite(OMC_DB, "SELECT id, title, description FROM todos WHERE status='done' ORDER BY updated_at DESC LIMIT 20;")
    completed_todos = [{"id": r.get("id",""), "title": r.get("title",""), "description": r.get("description","")} for r in rows]
    diag(f"completedTodos={len(completed_todos)}")
else:
    diag("omc-memory.db not found")

# ─── D. agentQTable ───────────────────────────────────────────────────────────
agent_q_table = []
if os.path.isfile(OMC_DB):
    rows = run_sqlite(OMC_DB, "SELECT task_signature, agent_id, q_value, trials FROM agent_q_table ORDER BY q_value DESC LIMIT 30;")
    agent_q_table = [{"task_signature": r.get("task_signature",""), "agent_id": r.get("agent_id",""), "q_value": float(r.get("q_value",0)), "trials": int(r.get("trials",0))} for r in rows]
    diag(f"agentQTable rows={len(agent_q_table)}")

# ─── E. mcpSignals ────────────────────────────────────────────────────────────
mcp_signals = {"serverNames": [], "commandHints": [], "domainTags": []}

mcp_paths = [MCP_CONFIG]
if os.path.isfile(MCP_CONFIG):
    mcp_paths = [MCP_CONFIG]
else:
    for candidate in [
        os.path.expanduser("~/.copilot/mcp.json"),
        os.path.join(PLUGIN_ROOT, "mcp.json"),
    ]:
        if os.path.isfile(candidate):
            mcp_paths = [candidate]
            break

for mcp_path in mcp_paths:
    if not os.path.isfile(mcp_path):
        continue
    try:
        with open(mcp_path, encoding="utf-8") as f:
            mcp = json.load(f)
        servers = mcp.get("mcpServers", mcp.get("servers", {}))
        for name, cfg in servers.items():
            mcp_signals["serverNames"].append(name)
            args = cfg.get("args", [])
            if args:
                mcp_signals["commandHints"].append(" ".join(str(a) for a in args[:3]))
    except Exception as e:
        diag(f"mcp.json parse error: {e}")

domain_keyword_map = {
    "browser":    r"browser|playwright|puppeteer|selenium",
    "github":     r"github|octokit|gh\b|pull.request|repo",
    "database":   r"sqlite|postgres|mysql|mongo|db\b",
    "filesystem": r"fs\b|file.*system|directory|glob|walk",
    "devtools":   r"devtools|chrome|debug|inspect",
    "research":   r"search|semantic|rag|vector|embed",
}
server_text = " ".join(mcp_signals["serverNames"] + mcp_signals["commandHints"]).lower()
for domain, pattern in domain_keyword_map.items():
    if re.search(pattern, server_text):
        mcp_signals["domainTags"].append(domain)

diag(f"mcpSignals.serverNames={len(mcp_signals['serverNames'])}")

# ─── F. dominantDomains ───────────────────────────────────────────────────────
corpus_parts = [d["path"] for d in top_directories]
corpus_parts += [f"{t['title']} {t['description']}" for t in completed_todos]
corpus_parts += mcp_signals["serverNames"] + mcp_signals["commandHints"]
corpus = " ".join(corpus_parts).lower()

domain_patterns = {
    "youtube":    r"youtube|video|shorts|broll|thumbnail|trend",
    "typescript": r"typescript|\bts\b|\.ts\b|react|tsx|nextjs|vite",
    "api":        r"\bapi\b|endpoint|\bfetch\b|rest\b|webhook|\bhttp\b",
    "finance":    r"stock|finance|dividend|earning|financial|chart|ticker",
    "devops":     r"\bgit\b|github|commit|deploy|\bci\b|\bcd\b|pipeline",
    "content":    r"blog|content|\bpost\b|autoblog|creator|shopping",
}

dominant_domains = []
for domain, pattern in domain_patterns.items():
    if re.search(pattern, corpus):
        dominant_domains.append(domain)

for mcp_domain in mcp_signals["domainTags"]:
    if mcp_domain not in dominant_domains:
        dominant_domains.append(mcp_domain)

diag(f"dominantDomains={dominant_domains}")

# ─── G. suggestedAgentNames ───────────────────────────────────────────────────
agent_name_map = {
    "youtube":    "my-youtube-specialist",
    "typescript": "my-typescript-expert",
    "finance":    "my-finance-analyst",
    "api":        "my-api-specialist",
    "devops":     "my-devops-engineer",
    "content":    "my-content-creator",
    "browser":    "my-browser-automation-specialist",
    "devtools":   "my-devtools-debugger",
    "github":     "my-github-workflow-optimizer",
    "database":   "my-database-specialist",
    "filesystem": "my-filesystem-automation-specialist",
    "research":   "my-research-assistant",
}

suggested_agent_names = [agent_name_map[d] for d in dominant_domains if d in agent_name_map]

# ─── H. Emit JSON ─────────────────────────────────────────────────────────────
output = {
    "analysisDate":        datetime.now().strftime("%Y-%m-%dT%H:%M:%S"),
    "sessionCount":        session_count,
    "topDirectories":      top_directories,
    "completedTodos":      completed_todos,
    "agentQTable":         agent_q_table,
    "dominantDomains":     dominant_domains,
    "suggestedAgentNames": suggested_agent_names,
    "mcpSignals":          mcp_signals,
}
print(json.dumps(output, ensure_ascii=False, indent=2))
PYEOF
