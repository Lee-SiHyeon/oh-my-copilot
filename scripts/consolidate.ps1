# omc Memory Consolidation Script
# Runs at sessionEnd: extracts semantic facts from session logs → SQLite
# Implements: Memory Admission Control + Priority Decay update

param(
    [string]$DbPath,
    [string]$LearnPath,
    [string]$LogPath,
    [float]$Alpha = 0.1    # Q-Learning update rate
)

$ErrorActionPreference = 'SilentlyContinue'

function Get-HomeDirectory {
    if (-not [string]::IsNullOrWhiteSpace($HOME)) { return $HOME }
    return [Environment]::GetFolderPath('UserProfile')
}

function Get-CopilotRoot {
    Join-Path (Get-HomeDirectory) '.copilot'
}

function Get-PluginRoot {
    Split-Path -Parent $PSScriptRoot
}

function Test-IsWindows {
    $env:OS -eq 'Windows_NT'
}

function Resolve-Sqlite3Path {
    $command = Get-Command sqlite3 -ErrorAction SilentlyContinue
    if ($command -and $command.Source) { return $command.Source }

    $command = Get-Command sqlite3.exe -ErrorAction SilentlyContinue
    if ($command -and $command.Source) { return $command.Source }

    if (Test-IsWindows) {
        $localAppData = $env:LOCALAPPDATA
        if (-not [string]::IsNullOrWhiteSpace($localAppData)) {
            $wingetPath = Join-Path $localAppData 'Microsoft\WinGet\Packages\SQLite.SQLite_Microsoft.Winget.Source_8wekyb3d8bbwe\sqlite3.exe'
            if (Test-Path $wingetPath) { return $wingetPath }
        }
    }

    $pathEntries = New-Object System.Collections.ArrayList
    foreach ($pathValue in @($env:PATH, [Environment]::GetEnvironmentVariable('PATH', 'User'), [Environment]::GetEnvironmentVariable('PATH', 'Machine'))) {
        if ([string]::IsNullOrWhiteSpace($pathValue)) { continue }
        foreach ($entry in ($pathValue -split [IO.Path]::PathSeparator)) {
            if (-not [string]::IsNullOrWhiteSpace($entry) -and -not ($pathEntries -contains $entry)) {
                [void]$pathEntries.Add($entry)
            }
        }
    }

    foreach ($entry in $pathEntries) {
        foreach ($candidateName in @('sqlite3', 'sqlite3.exe')) {
            $candidate = Join-Path $entry $candidateName
            if (Test-Path $candidate) { return $candidate }
        }
    }

    return $null
}

if ([string]::IsNullOrWhiteSpace($DbPath)) {
    $DbPath = Join-Path (Get-PluginRoot) 'omc-memory.db'
}
if ([string]::IsNullOrWhiteSpace($LearnPath)) {
    $LearnPath = Join-Path (Get-PluginRoot) 'LEARNINGS.md'
}
if ([string]::IsNullOrWhiteSpace($LogPath)) {
    $LogPath = Join-Path (Get-CopilotRoot) 'session.log'
}

$sqlite3 = Resolve-Sqlite3Path
if (-not $sqlite3) { exit 0 }  # silently skip if sqlite3 unavailable

if (-not (Test-Path $DbPath)) {
    Write-Host "[omc] Memory DB not found, skipping consolidation"
    exit 0
}

function Invoke-Sqlite {
    param([string]$Query)
    $Query | & $sqlite3 $DbPath
}

# ── 1. Update last_accessed on recently used semantic facts ─────────────────
Invoke-Sqlite "UPDATE semantic_memory SET last_accessed = CURRENT_TIMESTAMP, access_count = access_count + 1 WHERE last_accessed < datetime('now', '-1 day');"

# ── 2. Priority Decay eviction: remove facts with score < 0.01 ──────────────
#   score = (base_importance * access_count) / (days_since_access + 1)
Invoke-Sqlite @"
DELETE FROM semantic_memory
WHERE (base_importance * access_count) / (CAST(julianday('now') - julianday(last_accessed) AS REAL) + 1) < 0.01
AND creation_time < datetime('now', '-30 days');
"@

# ── 3. Extract new learnings from LEARNINGS.md ──────────────────────────────
if (Test-Path $LearnPath) {
    $lines = Get-Content $LearnPath | Where-Object { $_ -match '^\[' } | Select-Object -Last 10
    foreach ($line in $lines) {
        # Memory Admission Control: skip low-signal entries
        $isLowSignal = ($line.Length -lt 30) -or ($line -match 'No agent changes')
        if ($isLowSignal) { continue }

        # Detect category
        $category = switch -Regex ($line) {
            'agent|atlas|hook'           { 'agent' }
            'error|fail|crash|bug'       { 'error' }
            'pattern|approach|strategy'  { 'pattern' }
            'nlm|research|notebook'      { 'tool' }
            default                      { 'general' }
        }

        $escaped = $line -replace "'", "''"
        $tokenWeight = [Math]::Min([Math]::Round($line.Length / 10), 100)

        # Insert with de-duplication
        Invoke-Sqlite @"
INSERT INTO semantic_memory (fact_content, category, token_weight, base_importance)
SELECT '$escaped', '$category', $tokenWeight, 1.0
WHERE NOT EXISTS (
    SELECT 1 FROM semantic_memory
    WHERE fact_content = '$escaped'
);
"@
    }
}

# ── 4. Report top 3 memories by priority score ──────────────────────────────
$top = Invoke-Sqlite @"
SELECT fact_content,
       ROUND((base_importance * access_count) / (CAST(julianday('now') - julianday(last_accessed) AS REAL) + 1), 3) AS score
FROM semantic_memory
ORDER BY score DESC
LIMIT 3;
"@

if ($top) {
    Write-Host "[omc] Top memories by priority:"
    $top | ForEach-Object { Write-Host "  $_" }
}

# ── 5. Summarize DB state ────────────────────────────────────────────────────
$counts = Invoke-Sqlite "SELECT 'semantic_memory', COUNT(*) FROM semantic_memory UNION ALL SELECT 'meta_policy_rules', COUNT(*) FROM meta_policy_rules UNION ALL SELECT 'agent_q_table', COUNT(*) FROM agent_q_table;"
Write-Host "[omc] Memory DB: $($counts -join ' | ')"
