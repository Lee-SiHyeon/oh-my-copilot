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
      agentQTable, dominantDomains, suggestedAgentNames, mcpSignals

.EXAMPLE
    powershell -File scripts\collect-session-data.ps1
    powershell -File scripts\collect-session-data.ps1 -Depth 7 -Verbose
#>

# NOTE: Kept compatible with Windows PowerShell 5.1 while also running under pwsh.
#       Avoids PS7-only operators (?. and ??) for maximum portability.
param(
    [int]$Depth = 30,   # look-back window in days
    [switch]$Verbose    # diagnostic output to stderr (stdout stays JSON)
)

$ErrorActionPreference = 'SilentlyContinue'

# ─── platform helpers ──────────────────────────────────────────────────────────

function Write-Diag {
    param([string]$Msg)
    if ($Verbose) { [Console]::Error.WriteLine("[collect-session-data] $Msg") }
}

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

function Get-PathLeaf {
    param([string]$PathText)

    if ([string]::IsNullOrWhiteSpace($PathText)) { return '' }

    $trimmed = $PathText.Trim().TrimEnd('\', '/')
    if ([string]::IsNullOrWhiteSpace($trimmed)) { return '' }

    $leaf = Split-Path -Path $trimmed -Leaf -ErrorAction SilentlyContinue
    if (-not [string]::IsNullOrWhiteSpace($leaf)) { return $leaf }

    $parts = $trimmed -split '[\\/]'
    if ($parts.Count -gt 0) { return $parts[$parts.Count - 1] }

    return ''
}

# ─── generic helpers ───────────────────────────────────────────────────────────

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

function Add-UniqueString {
    param(
        [System.Collections.ArrayList]$List,
        [string]$Value
    )

    if ($null -eq $List) { return }
    if ([string]::IsNullOrWhiteSpace($Value)) { return }

    $trimmed = $Value.Trim()
    foreach ($existing in $List) {
        if ("$existing" -ieq $trimmed) { return }
    }

    [void]$List.Add($trimmed)
}

function Get-ObjectProperties {
    param($InputObject)

    $pairs = @()
    if ($null -eq $InputObject) { return $pairs }
    if ($InputObject -is [string]) { return $pairs }

    if ($InputObject -is [System.Collections.IDictionary]) {
        foreach ($key in $InputObject.Keys) {
            $pairs += [PSCustomObject]@{
                Name  = "$key"
                Value = $InputObject[$key]
            }
        }
        return $pairs
    }

    foreach ($prop in $InputObject.PSObject.Properties) {
        if ($prop.MemberType -match 'Property|NoteProperty') {
            $pairs += [PSCustomObject]@{
                Name  = "$($prop.Name)"
                Value = $prop.Value
            }
        }
    }

    return $pairs
}

function Remove-JsonComments {
    param([string]$Text)

    if ([string]::IsNullOrEmpty($Text)) { return $Text }

    $sb             = New-Object System.Text.StringBuilder
    $inString       = $false
    $isEscaped      = $false
    $inLineComment  = $false
    $inBlockComment = $false

    for ($i = 0; $i -lt $Text.Length; $i++) {
        $ch   = $Text[$i]
        $next = if ($i + 1 -lt $Text.Length) { $Text[$i + 1] } else { [char]0 }

        if ($inLineComment) {
            if ($ch -eq "`r" -or $ch -eq "`n") {
                $inLineComment = $false
                [void]$sb.Append($ch)
            }
            continue
        }

        if ($inBlockComment) {
            if ($ch -eq '*' -and $next -eq '/') {
                $inBlockComment = $false
                $i++
            }
            continue
        }

        if ($inString) {
            [void]$sb.Append($ch)

            if ($isEscaped) {
                $isEscaped = $false
            } elseif ($ch -eq '\') {
                $isEscaped = $true
            } elseif ($ch -eq '"') {
                $inString = $false
            }
            continue
        }

        if ($ch -eq '"') {
            $inString = $true
            [void]$sb.Append($ch)
            continue
        }

        if ($ch -eq '/' -and $next -eq '/') {
            $inLineComment = $true
            $i++
            continue
        }

        if ($ch -eq '/' -and $next -eq '*') {
            $inBlockComment = $true
            $i++
            continue
        }

        [void]$sb.Append($ch)
    }

    $sb.ToString()
}

function Remove-TrailingJsonCommas {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return $Text }

    $result = $Text
    do {
        $previous = $result
        $result   = [regex]::Replace($result, ',(?=\s*[\}\]])', '')
    } while ($result -ne $previous)

    $result
}

function ConvertFrom-JsonLike {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }

    $normalised = Remove-JsonComments $Text
    $normalised = Remove-TrailingJsonCommas $normalised

    try {
        return $normalised | ConvertFrom-Json -ErrorAction Stop
    } catch {
        return $null
    }
}

function Test-McpHintText {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }

    return (
        $Text -imatch '\bmcp\b' -or
        $Text -imatch 'modelcontextprotocol' -or
        $Text -imatch 'server[-_/](github|filesystem|sqlite|postgres|mysql|browser|playwright|puppeteer|devtools|fetch|api|search|notion)'
    )
}

function Test-McpConfigText {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }

    return (
        $Text -imatch '"[^"]*mcp[^"]*"\s*:' -or
        $Text -imatch '\bmcpServers\b' -or
        $Text -imatch 'modelcontextprotocol'
    )
}

function Add-DomainTagsFromText {
    param(
        [string]$Text,
        [hashtable]$State
    )

    if ([string]::IsNullOrWhiteSpace($Text)) { return }

    $tagPatterns = [ordered]@{
        browser    = 'browser|playwright|puppeteer|chrome|edge|firefox'
        devtools   = 'devtools|chrome-devtools|inspector|debugger'
        github     = 'github|gitlab|\bgit\b|repo|repository|pull\s*request|issues?'
        database   = 'postgres|mysql|sqlite|sqlserver|mssql|mongodb|database|\bdb\b|redis'
        filesystem = 'filesystem|file\s*system|\bfiles?\b|\bdirector(y|ies)\b|\bpath\b|\bfs\b'
        api        = '\bapi\b|rest|graphql|endpoint|swagger|openapi|postman'
        research   = 'research|search|scholar|docs|documentation|wiki|knowledge|crawl'
        content    = 'content|blog|cms|markdown|notion|obsidian|writer|publish'
    }

    foreach ($tag in $tagPatterns.Keys) {
        if ($Text -imatch $tagPatterns[$tag]) {
            Add-UniqueString -List $State.domainTags -Value $tag
        }
    }
}

function Add-McpCommandHint {
    param(
        $Value,
        [hashtable]$State
    )

    if ($null -eq $Value) { return }

    $text = $null
    if ($Value -is [string]) {
        $text = $Value
    } elseif ($Value -is [System.Collections.IEnumerable]) {
        $parts = @()
        foreach ($item in $Value) {
            if ($null -ne $item) { $parts += "$item" }
        }
        $text = ($parts -join ' ').Trim()
    } else {
        $text = "$Value"
    }

    if ([string]::IsNullOrWhiteSpace($text)) { return }

    $compactText = ($text -replace '\s+', ' ').Trim()
    if ($compactText.Length -gt 400) {
        $compactText = $compactText.Substring(0, 400)
    }

    Add-UniqueString -List $State.commandHints -Value $compactText
    Add-DomainTagsFromText -Text $compactText -State $State

    $serverMatches = [regex]::Matches($compactText, '(?i)(?:@modelcontextprotocol/|server[-_/]|mcp[-_/])([a-z0-9._-]+)')
    foreach ($match in $serverMatches) {
        if ($match.Groups.Count -gt 1) {
            $serverName = $match.Groups[1].Value -replace '^(server|mcp)[-_/]', ''
            Add-UniqueString -List $State.serverNames -Value $serverName
            Add-DomainTagsFromText -Text $serverName -State $State
        }
    }
}

function Collect-McpSignalsFromNode {
    param(
        $Node,
        [string]$Path,
        [bool]$McpContext,
        [hashtable]$State
    )

    if ($null -eq $Node) { return }

    if ($Node -is [string]) {
        if ($McpContext -or (Test-McpHintText $Node)) {
            Add-McpCommandHint -Value $Node -State $State
        }
        return
    }

    $pairs = Get-ObjectProperties $Node
    if ($pairs.Count -gt 0) {
        foreach ($pair in $pairs) {
            $name         = "$($pair.Name)"
            $value        = $pair.Value
            $nextPath     = if ([string]::IsNullOrWhiteSpace($Path)) { $name } else { "$Path.$name" }
            $lowerName    = $name.ToLowerInvariant()
            $nameHasMcp   = ($lowerName -match '(^|[._-])mcp($|[._-])') -or ($lowerName -match 'modelcontextprotocol')
            $nextContext  = $McpContext -or $nameHasMcp
            $isServerProp = $lowerName -match 'servers?$'

            if ($nameHasMcp -or ($McpContext -and $lowerName -match 'servers?|name|id|command|args|path|url|endpoint|transport')) {
                Add-UniqueString -List $State.discoveredKeys -Value $nextPath
            }

            if ($nextContext -and $lowerName -match '^(name|id|servername)$' -and $value -is [string]) {
                Add-UniqueString -List $State.serverNames -Value $value
                Add-DomainTagsFromText -Text $value -State $State
            }

            if ($nextContext -and $lowerName -match 'command|cmd|executable|program|args') {
                Add-McpCommandHint -Value $value -State $State
            }

            if ($nextContext -and $isServerProp) {
                $serverPairs = Get-ObjectProperties $value
                foreach ($serverPair in $serverPairs) {
                    Add-UniqueString -List $State.serverNames -Value $serverPair.Name
                    Add-DomainTagsFromText -Text $serverPair.Name -State $State
                }
            }

            if ($value -is [string] -and (($nextContext -and (Test-McpHintText $value)) -or ($nameHasMcp -and -not [string]::IsNullOrWhiteSpace($value)))) {
                Add-McpCommandHint -Value $value -State $State
            }

            Collect-McpSignalsFromNode -Node $value -Path $nextPath -McpContext $nextContext -State $State
        }
        return
    }

    if ($Node -is [System.Collections.IEnumerable] -and -not ($Node -is [string])) {
        $index = 0
        foreach ($item in $Node) {
            $nextPath = if ([string]::IsNullOrWhiteSpace($Path)) { "[$index]" } else { "$Path[$index]" }
            Collect-McpSignalsFromNode -Node $item -Path $nextPath -McpContext $McpContext -State $State
            $index++
        }
    }
}

function Get-McpSignals {
    $state = @{
        configPaths    = New-Object System.Collections.ArrayList
        mcpConfigPaths = New-Object System.Collections.ArrayList
        discoveredKeys = New-Object System.Collections.ArrayList
        serverNames    = New-Object System.Collections.ArrayList
        commandHints   = New-Object System.Collections.ArrayList
        domainTags     = New-Object System.Collections.ArrayList
    }

    $candidatePaths = New-Object System.Collections.ArrayList
    $home           = Get-HomeDirectory
    $copilotRoot    = Get-CopilotRoot

    Add-UniqueString -List $candidatePaths -Value (Join-Path $copilotRoot 'config.json')

    if (Test-IsWindows) {
        if (-not [string]::IsNullOrWhiteSpace($env:APPDATA)) {
            Add-UniqueString -List $candidatePaths -Value (Join-Path $env:APPDATA 'Code\User\settings.json')
        }
    }

    $xdgConfigHome = $env:XDG_CONFIG_HOME
    if ([string]::IsNullOrWhiteSpace($xdgConfigHome)) {
        $xdgConfigHome = Join-Path $home '.config'
    }
    Add-UniqueString -List $candidatePaths -Value (Join-Path $xdgConfigHome 'Code/User/settings.json')
    Add-UniqueString -List $candidatePaths -Value (Join-Path $home 'Library/Application Support/Code/User/settings.json')

    if (Test-Path $copilotRoot) {
        $jsonFiles = Get-ChildItem $copilotRoot -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -in '.json', '.jsonc' }

        foreach ($file in $jsonFiles) {
            $pathText = $file.FullName
            $shouldInspect = $pathText -imatch '(mcp|modelcontextprotocol|config|settings|server).*\.jsonc?$'

            if (-not $shouldInspect) {
                $rawPreview = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
                if (-not [string]::IsNullOrWhiteSpace($rawPreview) -and (Test-McpConfigText $rawPreview)) {
                    $shouldInspect = $true
                }
            }

            if ($shouldInspect) {
                Add-UniqueString -List $candidatePaths -Value $pathText
            }
        }
    }

    foreach ($candidatePath in $candidatePaths) {
        if (-not (Test-Path $candidatePath)) { continue }

        Add-UniqueString -List $state.configPaths -Value $candidatePath

        $raw = Get-Content $candidatePath -Raw -ErrorAction SilentlyContinue
        if ([string]::IsNullOrWhiteSpace($raw)) { continue }

        $beforeSignalCount = $state.discoveredKeys.Count + $state.serverNames.Count + $state.domainTags.Count + $state.commandHints.Count

        $parsed = ConvertFrom-JsonLike $raw
        if ($null -ne $parsed) {
            Collect-McpSignalsFromNode -Node $parsed -Path '' -McpContext $false -State $state
        } elseif (Test-McpHintText $raw) {
            Add-UniqueString -List $state.discoveredKeys -Value 'textScanFallback'
            Add-McpCommandHint -Value $raw -State $state
        }

        $afterSignalCount = $state.discoveredKeys.Count + $state.serverNames.Count + $state.domainTags.Count + $state.commandHints.Count
        if ((Test-McpConfigText $raw) -or ($afterSignalCount -gt $beforeSignalCount)) {
            Add-UniqueString -List $state.mcpConfigPaths -Value $candidatePath
        }
    }

    Write-Diag "MCP config paths: $($state.configPaths.Count); servers: $($state.serverNames.Count); tags: $($state.domainTags.Count)"

    return [PSCustomObject][ordered]@{
        detectedConfigPath = if ($state.mcpConfigPaths.Count -gt 0) { "$($state.mcpConfigPaths[0])" } elseif ($state.configPaths.Count -gt 0) { "$($state.configPaths[0])" } else { "" }
        configPaths        = @($state.configPaths)
        discoveredKeys     = @($state.discoveredKeys)
        serverNames        = @($state.serverNames)
        commandHints       = @($state.commandHints)
        domainTags         = @($state.domainTags)
    }
}

# ─── A. Locate sqlite3 ────────────────────────────────────────────────────────

$sqlite3 = Resolve-Sqlite3Path
Write-Diag "sqlite3: $(if ($sqlite3) { $sqlite3 } else { 'NOT FOUND' })"

# ─── B. session.log analysis ──────────────────────────────────────────────────
#   Two formats in the wild:
#     Legacy : [2026-03-22 17:46:40] Session started in C:\path\to\dir
#     Current: [2026-03-22 18:55:52] SESSION_START cwd=C:\path\to\dir

$copilotRoot   = Get-CopilotRoot
$logPath       = Join-Path $copilotRoot 'session.log'
$cutoff        = (Get-Date).AddDays(-$Depth)
$sessionCount  = 0
$dirCounts     = @{}   # leaf-name → visit count

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
        $segment = Get-PathLeaf $cwdPath
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
    $sessionDbs = @()
    $sessionStateRoot = Join-Path $copilotRoot 'session-state'
    if (Test-Path $sessionStateRoot) {
        $sessionDbs = Get-ChildItem $sessionStateRoot -Directory -ErrorAction SilentlyContinue |
            ForEach-Object {
                $dbPath = Join-Path $_.FullName 'session.db'
                if (Test-Path $dbPath) {
                    Get-Item $dbPath -ErrorAction SilentlyContinue
                }
            } |
            Where-Object { $null -ne $_ }
    }

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
    $omcDb = Join-Path (Get-PluginRoot) 'omc-memory.db'

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

$mcpSignals = Get-McpSignals

$corpus = (
    @(($topDirectories | ForEach-Object { $_.path })) +
    @(($completedTodos  | ForEach-Object { "$($_.title) $($_.description)" })) +
    @($mcpSignals.serverNames) +
    @($mcpSignals.commandHints)
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

foreach ($mcpDomain in $mcpSignals.domainTags) {
    if ($dominantDomains -notcontains $mcpDomain) {
        $dominantDomains += $mcpDomain
    }
}

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
    browser    = 'my-browser-automation-specialist'
    devtools   = 'my-devtools-debugger'
    github     = 'my-github-workflow-optimizer'
    database   = 'my-database-specialist'
    filesystem = 'my-filesystem-automation-specialist'
    research   = 'my-research-assistant'
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
    mcpSignals          = $mcpSignals
} | ConvertTo-Json -Depth 5
