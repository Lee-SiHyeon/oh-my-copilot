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

$copilotRoot        = Get-CopilotRoot
$pluginRoot         = Get-PluginRoot
$logPath            = Join-Path $copilotRoot 'session.log'
$learnPath          = Join-Path $pluginRoot 'LEARNINGS.md'
$consolidateScript  = Join-Path $PSScriptRoot 'consolidate.ps1'
$timestamp          = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$currentDirectory   = (Get-Location).Path
$git                = Get-Command git -ErrorAction SilentlyContinue

if (-not $DryRun) {
    if (-not (Test-Path $copilotRoot)) {
        [void](New-Item -ItemType Directory -Path $copilotRoot -Force)
    }

    Add-Content -Path $logPath -Value "[$timestamp] SESSION_END cwd=$currentDirectory"
}

Push-Location $pluginRoot
try {
    if (-not $git) {
        Write-Host "[omc] Git not available, skipping auto-learn commit"
    } else {
        $status = @(& $git.Source status --porcelain 2>$null)

        if ($status.Count -gt 0) {
            if ($DryRun) {
                Write-Host "[omc] DryRun: would git add agents/ hooks.json scripts/"
                Write-Host "[omc] DryRun: would git commit -m `"auto-learn: $timestamp`" --no-verify"
                Write-Host "[omc] DryRun: would git push origin main"
                Write-Host "[omc] DryRun: would append auto-commit note to LEARNINGS.md"
            } else {
                [void](& $git.Source add agents/ hooks.json scripts/ 2>$null)
                $message = "auto-learn: $timestamp"
                [void](& $git.Source commit -m $message --no-verify 2>$null)
                [void](& $git.Source push origin main 2>$null)
                Add-Content -Path $learnPath -Value "[$timestamp] Auto-committed: $($status -join ', ')"
                Write-Host "[omc] Self-improved: committed agent changes"
            }
        } else {
            Write-Host "[omc] No agent changes to commit"
        }
    }

    if ($DryRun) {
        Write-Host "[omc] DryRun: would run $consolidateScript"
    } elseif (Test-Path $consolidateScript) {
        & $consolidateScript 2>$null
    }
} finally {
    Pop-Location
}
