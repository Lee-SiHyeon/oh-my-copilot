$ErrorActionPreference = 'SilentlyContinue'

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

function Test-CompliantTaskDelegationPrompt {
    param(
        [object]$ToolArgsObject
    )

    if ($null -eq $ToolArgsObject) { return $false }

    $prompt = "$($ToolArgsObject.prompt)"
    if ([string]::IsNullOrWhiteSpace($prompt)) { return $false }

    $requiredSections = @(
        '## 1. TASK',
        '## 2. EXPECTED OUTCOME',
        '## 3. REQUIRED TOOLS',
        '## 4. MUST DO',
        '## 5. MUST NOT DO',
        '## 6. CONTEXT'
    )

    foreach ($section in $requiredSections) {
        if ($prompt.IndexOf($section, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
            return $false
        }
    }

    return ($prompt -split '\r?\n').Count -ge 30
}

function Test-AgentPolicyContext {
    param(
        [string]$ToolName,
        [object]$ToolArgsObject
    )

    $normalizedToolName = ($ToolName -replace '[^a-zA-Z0-9]', '').ToLowerInvariant()
    $agentReadOnlyToolNames = @(
        'readagent',
        'listagents'
    )
    if ($normalizedToolName -in $agentReadOnlyToolNames) {
        return $false
    }

    $agentRelevantToolNames = @(
        'task',
        'delegate',
        'delegation',
        'delegateto',
        'subagent',
        'modelselect',
        'modelselection',
        'selectmodel'
    )
    if ($normalizedToolName -notin $agentRelevantToolNames) {
        return $false
    }

    $scalarEntries = Get-ScalarToolArgEntries -Value $ToolArgsObject
    if ($scalarEntries.Count -eq 0) { return $false }

    $modelFieldNames = @(
        'model',
        'modelname',
        'modelid',
        'modelselection',
        'selectedmodel'
    )
    $opusPattern = '(?i)\bclaude-opus(?:-[a-z0-9.]+)?\b|\bopus(?:-[a-z0-9.]+)?\b'
    $hasOpusModelSelection = @(
            $scalarEntries | Where-Object {
                @(Get-NormalizedPathFieldNames -Path $_.Path | Where-Object { $_ -in $modelFieldNames }).Count -gt 0 -and
                $_.Value -match $opusPattern
            }
        ).Count -gt 0
    if ($hasOpusModelSelection) {
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
    $hasAgentControlFields = @(
            $scalarEntries | Where-Object {
                @(Get-NormalizedPathFieldNames -Path $_.Path | Where-Object { $_ -in $agentFieldNames }).Count -gt 0 -and
                -not [string]::IsNullOrWhiteSpace($_.Value)
            }
        ).Count -gt 0
    if (-not $hasAgentControlFields) {
        return $false
    }

    if ($normalizedToolName -eq 'task') {
        return -not (Test-CompliantTaskDelegationPrompt -ToolArgsObject $ToolArgsObject)
    }

    return $true
}

function Ensure-OmcMemoryDb {
    param(
        [string]$Sqlite3Path
    )

    $stateRoot = Get-UserStateRoot
    $dbPath    = Join-Path $stateRoot 'omc-memory.db'
    $legacyDb  = Join-Path (Get-PluginRoot) 'omc-memory.db'

    if (-not (Test-Path $stateRoot)) {
        [void](New-Item -ItemType Directory -Path $stateRoot -Force)
    }

    if (-not (Test-Path $dbPath)) {
        if (Test-Path $legacyDb) {
            Copy-Item -Path $legacyDb -Destination $dbPath -Force
        } elseif (-not [string]::IsNullOrWhiteSpace($Sqlite3Path)) {
            $initScript = Join-Path $PSScriptRoot 'init-memory.ps1'
            if (Test-Path $initScript) {
                [void](& $initScript -DbPath $dbPath 2>$null)
            }
        }
    }

    return $dbPath
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

$shellLikeToolNames = @('bash', 'shell', 'powershell', 'execute')

$dangerousPatterns = @(
    'rm -rf',
    'rm -r -force',
    'Remove-Item -Recurse -Force',
    'git push --force',
    'git push -f',
    'DROP TABLE',
    'DELETE FROM',
    'format-volume',
    'format.com',
    'format ',
    'del /f /s',
    'rd /s /q'
)

$matchedDangerousPatterns = @(
    $dangerousPatterns | Where-Object {
        $toolArgs.IndexOf($_, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
    }
)

$matchedDangerousGitPatterns = @(
    $matchedDangerousPatterns | Where-Object {
        $_ -like 'git *'
    }
)

if (($toolName -in $shellLikeToolNames) -and $matchedDangerousPatterns.Count -gt 0) {
    Write-PermissionDecision -Decision 'ask' -Reason "Dangerous operation detected: $($matchedDangerousPatterns -join '; ')"
    return
}

$sqlite3 = Resolve-Sqlite3Path
$dbPath  = Ensure-OmcMemoryDb -Sqlite3Path $sqlite3

if (-not $sqlite3 -or -not (Test-Path $dbPath)) { return }

$domain = ''
if ($matchedDangerousGitPatterns.Count -gt 0) {
    $domain = 'git'
} elseif (Test-AgentPolicyContext -ToolName $toolName -ToolArgsObject $toolArgsObject) {
    $domain = 'agent'
} elseif (($toolName -in $shellLikeToolNames) -and ($toolArgs -imatch 'rm\s+-rf|remove-item\b.*-recurse|del\s+/f\s+/s|rd\s+/s\s+/q')) {
    $domain = 'file_io'
}

if ([string]::IsNullOrWhiteSpace($domain)) { return }

$rules = Invoke-SqliteQuery -Sqlite3Path $sqlite3 -DbPath $dbPath -Query "SELECT action_constraint FROM meta_policy_rules WHERE task_domain='$domain' AND is_active=1;"
if ($rules.Count -gt 0) {
    Write-PermissionDecision -Decision 'ask' -Reason "Policy check ($domain): $($rules -join '; ')"
}
