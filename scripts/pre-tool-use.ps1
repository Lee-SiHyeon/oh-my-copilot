$ErrorActionPreference = 'SilentlyContinue'

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

function Write-PermissionDecision {
    param(
        [string]$Decision,
        [string]$Reason
    )

    @{
        permissionDecision       = $Decision
        permissionDecisionReason = $Reason
    } | ConvertTo-Json -Compress
}

function Get-ScalarToolArgEntries {
    param(
        [object]$Value,
        [string]$Path = ''
    )

    if ($null -eq $Value) { return @() }

    if ($Value -is [System.Collections.IDictionary]) {
        $entries = @()
        foreach ($key in $Value.Keys) {
            $childPath = if ([string]::IsNullOrWhiteSpace($Path)) { "$key" } else { "$Path.$key" }
            $entries += Get-ScalarToolArgEntries -Value $Value[$key] -Path $childPath
        }
        return $entries
    }

    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $entries = @()
        foreach ($property in $Value.PSObject.Properties) {
            $childPath = if ([string]::IsNullOrWhiteSpace($Path)) { $property.Name } else { "$Path.$($property.Name)" }
            $entries += Get-ScalarToolArgEntries -Value $property.Value -Path $childPath
        }
        return $entries
    }

    if (($Value -is [System.Collections.IEnumerable]) -and -not ($Value -is [string])) {
        $entries = @()
        $index = 0
        foreach ($item in $Value) {
            $childPath = if ([string]::IsNullOrWhiteSpace($Path)) { "[$index]" } else { "$Path[$index]" }
            $entries += Get-ScalarToolArgEntries -Value $item -Path $childPath
            $index++
        }
        return $entries
    }

    return @([PSCustomObject]@{
        Path  = $Path
        Value = "$Value"
    })
}

function Get-NormalizedPathFieldNames {
    param(
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return @() }

    $fieldNames = @()
    foreach ($segment in ($Path -split '\.')) {
        if ([string]::IsNullOrWhiteSpace($segment)) { continue }

        $baseSegment = ($segment -replace '\[\d+\]', '')
        if ([string]::IsNullOrWhiteSpace($baseSegment)) { continue }

        $fieldNames += (($baseSegment -replace '[^a-zA-Z0-9]', '').ToLowerInvariant())
    }

    return $fieldNames
}

function Test-AgentPolicyContext {
    param(
        [string]$ToolName,
        [object]$ToolArgsObject
    )

    if ($ToolName -imatch '(^|[-_])(agent|delegate|delegation|subagent|model[-_]?select(?:ion)?)([-_]|$)') {
        return $true
    }

    $scalarEntries = Get-ScalarToolArgEntries -Value $ToolArgsObject
    if ($scalarEntries.Count -eq 0) { return $false }

    $opusPattern = '(?i)\bclaude-opus(?:-[a-z0-9.]+)?\b|\bopus(?:-[a-z0-9.]+)?\b'
    if (@($scalarEntries | Where-Object { $_.Value -match $opusPattern }).Count -gt 0) {
        return $true
    }

    $agentFieldNames = @(
        'agent',
        'agentname',
        'agenttype',
        'subagent',
        'delegate',
        'delegateto',
        'delegation',
        'model',
        'modelname',
        'modelid',
        'modelselection',
        'selectedmodel',
        'assistant'
    )
    if (@(
            $scalarEntries | Where-Object {
                @(Get-NormalizedPathFieldNames -Path $_.Path | Where-Object { $_ -in $agentFieldNames }).Count -gt 0 -and
                -not [string]::IsNullOrWhiteSpace($_.Value)
            }
        ).Count -gt 0) {
        return $true
    }

    return $false
}

$rawInput = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($rawInput)) { return }

try {
    $inputObject = $rawInput | ConvertFrom-Json -ErrorAction Stop
} catch {
    return
}

$toolName = "$($inputObject.toolName)"
$toolArgsObject = $inputObject.toolArgs
$toolArgs = ''
if ($null -ne $toolArgsObject) {
    $toolArgs = $toolArgsObject | ConvertTo-Json -Compress -Depth 10
}

$dangerousPatterns = @(
    'rm -rf',
    'rm -r -force',
    'Remove-Item -Recurse -Force',
    'git push --force',
    'git push -f',
    'DROP TABLE',
    'DELETE FROM',
    'format',
    'del /f /s',
    'rd /s /q'
)

$matchedDangerousPatterns = @(
    $dangerousPatterns | Where-Object {
        $toolArgs.IndexOf($_, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
    }
)

if (($toolName -in @('bash', 'shell', 'powershell', 'execute')) -and $matchedDangerousPatterns.Count -gt 0) {
    Write-PermissionDecision -Decision 'ask' -Reason "Dangerous operation detected: $($matchedDangerousPatterns -join '; ')"
    return
}

$pluginRoot = Get-PluginRoot
$dbPath     = Join-Path $pluginRoot 'omc-memory.db'
$sqlite3    = Resolve-Sqlite3Path

if (-not $sqlite3 -or -not (Test-Path $dbPath)) { return }

$domain = ''
if ($toolArgs -match '\bgit\b') {
    $domain = 'git'
} elseif (Test-AgentPolicyContext -ToolName $toolName -ToolArgsObject $toolArgsObject) {
    $domain = 'agent'
} elseif ($toolArgs -imatch 'rm\s+-rf|remove-item\b.*-recurse|del\s+/f\s+/s|rd\s+/s\s+/q') {
    $domain = 'file_io'
}

if ([string]::IsNullOrWhiteSpace($domain)) { return }

$rules = Invoke-SqliteQuery -Sqlite3Path $sqlite3 -DbPath $dbPath -Query "SELECT action_constraint FROM meta_policy_rules WHERE task_domain='$domain' AND is_active=1;"
if ($rules.Count -gt 0) {
    Write-PermissionDecision -Decision 'ask' -Reason "Policy check ($domain): $($rules -join '; ')"
}
