param(
    [switch]$DryRun
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

function Invoke-SqliteQuery {
    param(
        [string]$Sqlite3Path,
        [string]$DbPath,
        [string]$Query
    )

    if ([string]::IsNullOrWhiteSpace($Sqlite3Path)) { return @() }
    if (-not (Test-Path $DbPath)) { return @() }

    @($Query | & $Sqlite3Path $DbPath 2>$null)
}

$copilotRoot = Get-CopilotRoot
$pluginRoot  = Get-PluginRoot
$logPath     = Join-Path $copilotRoot 'session.log'
$dbPath      = Join-Path $pluginRoot 'omc-memory.db'
$learnPath   = Join-Path $pluginRoot 'LEARNINGS.md'
$agentsDir   = Join-Path $copilotRoot 'agents'
$timestamp   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$cwd         = (Get-Location).Path

if (-not $DryRun) {
    if (-not (Test-Path $copilotRoot)) {
        [void](New-Item -ItemType Directory -Path $copilotRoot -Force)
    }

    Add-Content -Path $logPath -Value "[$timestamp] SESSION_START cwd=$cwd"
}

$sqlite3 = Resolve-Sqlite3Path
if ($sqlite3 -and (Test-Path $dbPath)) {
    $topMemories = Invoke-SqliteQuery -Sqlite3Path $sqlite3 -DbPath $dbPath -Query "SELECT fact_content FROM semantic_memory ORDER BY (base_importance * access_count) / (CAST(julianday('now') - julianday(last_accessed) AS REAL) + 1) DESC LIMIT 5;"
    if ($topMemories.Count -gt 0) {
        Write-Host "[omc] Top memories: $($topMemories -join ' | ')"
    }
}

if (Test-Path $learnPath) {
    $lastLearnings = Get-Content $learnPath -ErrorAction SilentlyContinue | Select-Object -Last 3
    if ($lastLearnings) {
        Write-Host "[omc] Last learnings: $($lastLearnings -join ' | ')"
    }
}

if (Test-Path $agentsDir) {
    $myAgents = Get-ChildItem -Path $agentsDir -Filter '*.agent.md' -ErrorAction SilentlyContinue |
        ForEach-Object { $_.BaseName -replace '\.agent$', '' }

    if ($myAgents) {
        Write-Host "[omc] Your personal agents: $($myAgents -join ', ')"
    } else {
        Write-Host "[omc] No personal agents yet. Run: /agent oh-my-copilot:personal-advisor"
    }
}
