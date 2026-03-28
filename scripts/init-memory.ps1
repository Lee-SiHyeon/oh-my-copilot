# omc Memory System Initializer
# Creates omc-memory.db with 3 cognitive architecture tables:
#   1. semantic_memory   — distilled facts with Priority Decay (MaRS pattern)
#   2. meta_policy_rules — predicate rules with Hard Admissibility Checks (MPR pattern)
#   3. agent_q_table     — Q-Learning routing scores per task type

param(
    [string]$DbPath
)

$ErrorActionPreference = 'Stop'

function Get-PluginRoot {
    Split-Path -Parent $PSScriptRoot
}

function Get-HomeDirectory {
    if (-not [string]::IsNullOrWhiteSpace($HOME)) { return $HOME }
    return [Environment]::GetFolderPath('UserProfile')
}

function Get-CopilotRoot {
    Join-Path (Get-HomeDirectory) '.copilot'
}

function Get-UserStateRoot {
    Join-Path (Get-CopilotRoot) 'oh-my-copilot'
}

function Test-IsWSL {
    # WSL sets WSL_DISTRO_NAME; fallback to /proc/version for older WSL1
    [bool]($env:WSL_DISTRO_NAME -or (Test-Path '/proc/version' -ErrorAction SilentlyContinue))
}

function Test-IsWindows {
    # Exclude WSL: WSL reports OS=Windows_NT but is a Linux environment
    (-not (Test-IsWSL)) -and ($env:OS -eq 'Windows_NT')
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
    $DbPath = Join-Path (Get-UserStateRoot) 'omc-memory.db'
}

$parentDirectory = Split-Path -Parent $DbPath
if (-not [string]::IsNullOrWhiteSpace($parentDirectory) -and -not (Test-Path $parentDirectory)) {
    [void](New-Item -ItemType Directory -Path $parentDirectory -Force)
}

$legacyDbPath = Join-Path (Get-PluginRoot) 'omc-memory.db'
if (($DbPath -ne $legacyDbPath) -and -not (Test-Path $DbPath) -and (Test-Path $legacyDbPath)) {
    Copy-Item -Path $legacyDbPath -Destination $DbPath -Force
    Write-Host "[omc] Migrated legacy memory DB to user-local state: $DbPath"
}

$sqlite3 = Resolve-Sqlite3Path
if (-not $sqlite3) {
    Write-Error "sqlite3 not found in PATH"
    exit 1
}

$schema = @"
CREATE TABLE IF NOT EXISTS semantic_memory (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    fact_content    TEXT    NOT NULL,
    category        TEXT    DEFAULT 'general',     -- agent/tool/pattern/error/preference
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
    task_domain          TEXT    NOT NULL,          -- git / file_io / api / agent_delegation
    predicate_condition  TEXT    NOT NULL,          -- IF trigger
    action_constraint    TEXT    NOT NULL,          -- THEN MUST rule
    confidence_weight    REAL    DEFAULT 1.0,       -- rises when rule prevents failure
    violation_count      INTEGER DEFAULT 0,
    is_active            INTEGER DEFAULT 1,
    created_at           DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS agent_q_table (
    task_signature       TEXT    NOT NULL,          -- task type: code/debug/research/refactor
    agent_id             TEXT    NOT NULL,          -- hephaestus / sisyphus-junior / nlm-researcher / etc.
    q_value              REAL    DEFAULT 0.0,       -- expected reward Q(s,a)
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

-- Seed meta_policy_rules with known omc rules
INSERT OR IGNORE INTO meta_policy_rules (id, task_domain, predicate_condition, action_constraint)
VALUES
    (1, 'git',       'force push',            'MUST ask user confirmation before git push --force'),
    (2, 'file_io',   'recursive delete',      'MUST confirm before Remove-Item -Recurse -Force'),
    (3, 'agent',     'opus model requested',  'MUST refuse and use Sonnet instead'),
    (4, 'agent',     'delegation prompt',     'MUST include all 6 sections, minimum 30 lines'),
    (5, 'nlm',       'new research start',    'MUST import previous research before starting new');

-- Seed agent_q_table with reasonable starting Q-values
INSERT OR IGNORE INTO agent_q_table (task_signature, agent_id, q_value, trials) VALUES
    ('research',         'nlm-researcher',   1.0, 1),
    ('research',         'librarian',        0.7, 1),
    ('code_complex',     'hephaestus',       1.0, 1),
    ('code_simple',      'sisyphus-junior',  1.0, 1),
    ('planning',         'prometheus',       1.0, 1),
    ('debugging',        'oracle',           1.0, 1),
    ('codebase_search',  'explore',          1.0, 1);
"@

$schema | & $sqlite3 $DbPath
if ($LASTEXITCODE -eq 0) {
    Write-Host "[omc] Memory DB initialized: $DbPath"
    Write-Host "[omc] Tables: semantic_memory, meta_policy_rules, agent_q_table, improvement_candidates"
    "SELECT name FROM sqlite_master WHERE type='table';" | & $sqlite3 $DbPath
} else {
    Write-Error "[omc] Failed to initialize memory DB"
}
