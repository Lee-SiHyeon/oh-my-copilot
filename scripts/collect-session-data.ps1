<#
.SYNOPSIS
    Collects omc session history and outputs a structured JSON report to stdout.
    Consumed by the personal-advisor agent to recommend personalised agents.

.PARAMETER Depth
    Number of days to look back when analysing session.log. Default: 30.

.PARAMETER Verbose
    Emit diagnostic messages to stderr; stdout remains clean JSON.

.OUTPUTS
    UTF-8 JSON (stdout) conforming to the personal-advisor data contract:
      analysisDate, sessionCount, topDirectories, completedTodos,
      agentQTable, dominantDomains, suggestedAgentNames

.EXAMPLE
    powershell -File scripts\collect-session-data.ps1
    powershell -File scripts\collect-session-data.ps1 -Depth 7 -Verbose
#>

# NOTE: Written for Windows PowerShell 5.1+ compatibility.
#       Avoids PS7-only operators (?. and ??) for maximum portability.
param(
    [int]$Depth   = 30,   # look-back window in days
    [switch]$Verbose      # diagnostic output to stderr (stdout stays JSON)
)

$ErrorActionPreference = 'SilentlyContinue'

# ─── helpers ──────────────────────────────────────────────────────────────────

function Write-Diag {
    param([string]$Msg)
    if ($Verbose) { [Console]::Error.WriteLine("[collect-session-data] $Msg") }
}

# Escape a string for safe embedding in a JSON string literal.
# Used as a fallback; ConvertTo-Json handles full objects natively.
function ConvertTo-JsonString {
    param([string]$s)
    $s `
        -replace '\\', '\\' `
        -replace '"',  '\"' `
        -replace "`n", '\n' `
        -replace "`r", '\r' `
        -replace "`t", '\t'
}

# ─── A. Locate sqlite3 ────────────────────────────────────────────────────────

# 1. Try PATH first (works when sqlite3 is a globally installed tool)
$_cmd    = Get-Command sqlite3 -ErrorAction SilentlyContinue
$sqlite3 = if ($_cmd) { $_cmd.Source } else { $null }

# 2. Known WinGet install location (matches existing plugin convention)
if (-not $sqlite3) {
    $wingetPath = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\SQLite.SQLite_Microsoft.Winget.Source_8wekyb3d8bbwe\sqlite3.exe"
    if (Test-Path $wingetPath) { $sqlite3 = $wingetPath }
}

# 3. Brute-force machine PATH scan (handles non-standard installs)
if (-not $sqlite3) {
    $sqlite3 = [System.Environment]::GetEnvironmentVariable("PATH", "Machine").Split(";") |
        ForEach-Object { Join-Path $_ "sqlite3.exe" } |
        Where-Object   { Test-Path $_ } |
        Select-Object  -First 1
}

Write-Diag "sqlite3: $(if ($sqlite3) { $sqlite3 } else { 'NOT FOUND' })"

# ─── B. session.log analysis ──────────────────────────────────────────────────
#   Two formats in the wild:
#     Legacy : [2026-03-22 17:46:40] Session started in C:\path\to\dir
#     Current: [2026-03-22 18:55:52] SESSION_START cwd=C:\path\to\dir

$logPath      = "$env:USERPROFILE\.copilot\session.log"
$cutoff       = (Get-Date).AddDays(-$Depth)
$sessionCount = 0
$dirCounts    = @{}   # leaf-name → visit count

if (Test-Path $logPath) {
    $lines = Get-Content $logPath -ErrorAction SilentlyContinue

    foreach ($line in $lines) {

        # ── timestamp guard ──────────────────────────────────────────────────
        if ($line -notmatch '^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\]') { continue }
        try {
            $lineDate = [datetime]::ParseExact($Matches[1], 'yyyy-MM-dd HH:mm:ss', $null)
        } catch { continue }
        if ($lineDate -lt $cutoff) { continue }

        # ── path extraction (both formats) ───────────────────────────────────
        $cwdPath = $null
        if ($line -match 'SESSION_START\s+cwd=(.+)$') {
            $cwdPath = $Matches[1].Trim()
            $sessionCount++
        } elseif ($line -match 'Session started in (.+)$') {
            $cwdPath = $Matches[1].Trim()
            $sessionCount++
        } else {
            continue   # SESSION_END or unrecognised line — skip
        }

        if ([string]::IsNullOrWhiteSpace($cwdPath)) { continue }

        # Keep only the last path segment (e.g. "youtube-shorts-pipeline")
        $segment = Split-Path $cwdPath -Leaf
        if ([string]::IsNullOrWhiteSpace($segment)) { continue }

        if ($dirCounts.ContainsKey($segment)) {
            $dirCounts[$segment]++
        } else {
            $dirCounts[$segment] = 1
        }
    }

    Write-Diag "session.log: $sessionCount session(s) within last $Depth day(s)"
} else {
    Write-Diag "session.log not found — sessionCount will be 0"
}

# Build topDirectories array (top 10, descending visits)
$topDirectories = @()
if ($dirCounts.Count -gt 0 -and $sessionCount -gt 0) {
    $topDirectories = $dirCounts.GetEnumerator() |
        Sort-Object Value -Descending |
        Select-Object -First 10 |
        ForEach-Object {
            [PSCustomObject]@{
                path       = $_.Key
                visits     = [int]$_.Value
                percentage = [int][math]::Round(($_.Value / $sessionCount) * 100)
            }
        }
}

# ─── C. Completed todos from all session.db files ─────────────────────────────
#   session.db schema: todos(id, title, description, status, created_at, updated_at)
#   The UUID folder name serves as sessionId (no column exists in the table).
#   .mode json produces a JSON array — safe for titles/descriptions with commas.

$completedTodos = @()

if ($sqlite3) {
    $sessionDbs = Get-ChildItem "$env:USERPROFILE\.copilot\session-state\*\session.db" `
        -ErrorAction SilentlyContinue

    Write-Diag "Found $($sessionDbs.Count) session.db file(s)"

    foreach ($db in $sessionDbs) {
        $sessionId = $db.Directory.Name   # UUID directory name

        $sql = ".mode json`nSELECT title, description FROM todos WHERE status='done';"
        $jsonOut = $sql | & $sqlite3 $db.FullName 2>$null

        # sqlite3 outputs '[]' for zero rows; empty string means DB error
        if ([string]::IsNullOrWhiteSpace($jsonOut)) { continue }

        try {
            $rows = $jsonOut | ConvertFrom-Json -ErrorAction Stop
            foreach ($row in $rows) {
                $completedTodos += [PSCustomObject]@{
                    title       = "$($row.title)"
                    description = if ($null -ne $row.description) { "$($row.description)" } else { "" }
                    sessionId   = $sessionId
                }
            }
        } catch {
            Write-Diag "Parse error in $($db.FullName): $_"
        }
    }

    Write-Diag "Total completed todos collected: $($completedTodos.Count)"
} else {
    Write-Diag "sqlite3 not available — skipping todo collection"
}

# ─── D. omc-memory.db → agent_q_table ────────────────────────────────────────

$agentQTable = @()

if ($sqlite3) {
    $omcDb = "$env:USERPROFILE\.copilot\installed-plugins\oh-my-copilot\omc-memory.db"

    if (Test-Path $omcDb) {
        $sql = ".mode json`nSELECT task_signature, agent_id, q_value, trials FROM agent_q_table ORDER BY trials DESC;"
        $jsonOut = $sql | & $sqlite3 $omcDb 2>$null

        if (-not [string]::IsNullOrWhiteSpace($jsonOut)) {
            try {
                $rows = $jsonOut | ConvertFrom-Json -ErrorAction Stop
                foreach ($row in $rows) {
                    $agentQTable += [PSCustomObject]@{
                        task_signature = "$($row.task_signature)"
                        agent_id       = "$($row.agent_id)"
                        q_value        = [double]$row.q_value
                        trials         = [int]$row.trials
                    }
                }
            } catch {
                Write-Diag "Parse error in agent_q_table: $_"
            }
        }

        Write-Diag "agent_q_table rows: $($agentQTable.Count)"
    } else {
        Write-Diag "omc-memory.db not found at $omcDb"
    }
} else {
    Write-Diag "sqlite3 not available — skipping agent_q_table collection"
}

# ─── E. dominantDomains derivation ───────────────────────────────────────────
#   Build a single text corpus from directory names + todo text, then match
#   domain keyword groups. Order matters: more specific domains listed first.

$corpus = (
    @(($topDirectories | ForEach-Object { $_.path })) +
    @(($completedTodos  | ForEach-Object { "$($_.title) $($_.description)" }))
) -join ' '

# domain → keyword patterns (regex; \b = word boundary)
$domainPatterns = [ordered]@{
    youtube    = 'youtube|video|shorts|broll|thumbnail|trend'
    typescript = 'typescript|\bts\b|\.ts\b|react|tsx|nextjs|vite'
    api        = '\bapi\b|endpoint|\bfetch\b|rest\b|webhook|\bhttp\b'
    finance    = 'stock|finance|dividend|earning|financial|chart|ticker'
    devops     = '\bgit\b|github|commit|deploy|\bci\b|\bcd\b|pipeline'
    content    = 'blog|content|\bpost\b|autoblog|creator|shopping'
}

$dominantDomains = @(
    foreach ($domain in $domainPatterns.Keys) {
        if ($corpus -imatch $domainPatterns[$domain]) { $domain }
    }
)

Write-Diag "dominantDomains: $($dominantDomains -join ', ')"

# ─── F. suggestedAgentNames ───────────────────────────────────────────────────
#   kebab-case names, one per detected domain, for easy agent file naming.

$agentNameMap = @{
    youtube    = 'my-youtube-specialist'
    typescript = 'my-typescript-expert'
    finance    = 'my-finance-analyst'
    api        = 'my-api-specialist'
    devops     = 'my-devops-engineer'
    content    = 'my-content-creator'
}

$suggestedAgentNames = @(
    $dominantDomains |
        Where-Object { $agentNameMap.ContainsKey($_) } |
        ForEach-Object { $agentNameMap[$_] }
)

# ─── G. Emit structured JSON (stdout) ─────────────────────────────────────────
#   ConvertTo-Json -Depth 5 handles nested PSCustomObjects correctly.
#   @() wrappers guarantee arrays even when there is exactly 1 element.

[ordered]@{
    analysisDate        = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
    sessionCount        = $sessionCount
    topDirectories      = @($topDirectories)
    completedTodos      = @($completedTodos)
    agentQTable         = @($agentQTable)
    dominantDomains     = @($dominantDomains)
    suggestedAgentNames = @($suggestedAgentNames)
} | ConvertTo-Json -Depth 5
