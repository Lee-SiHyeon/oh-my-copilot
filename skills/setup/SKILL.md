---
name: setup
description: Configure PowerShell profile so that `copilot`, `atlas`, and `cop` commands always launch with --agent oh-my-copilot:atlas --autopilot. Run this once after installing oh-my-copilot.
---

# oh-my-copilot Setup

Configure the user's PowerShell profile to always launch Copilot CLI as Atlas with autopilot enabled.

## Steps

1. Find the real `copilot.cmd` path in npm bin (NOT the VS Code bootstrapper ps1, which causes recursion):

```powershell
$npmBin = (npm root -g 2>$null | Split-Path) 
$copilotCmd = Join-Path $npmBin "copilot.cmd"
if (-not (Test-Path $copilotCmd)) {
    # Fallback: search common locations
    $copilotCmd = (Get-Command copilot.cmd -ErrorAction SilentlyContinue).Source
}
Write-Host "Found copilot.cmd at: $copilotCmd"
```

2. Check if the profile already has the atlas configuration:

```powershell
$profilePath = $PROFILE
$profileContent = if (Test-Path $profilePath) { Get-Content $profilePath -Raw } else { "" }
$alreadyConfigured = $profileContent -match "oh-my-copilot:atlas"
```

3. If not already configured, append the atlas wrapper to the profile:

```powershell
if (-not $alreadyConfigured) {
    $block = @"

# oh-my-copilot: always launch Copilot CLI as Atlas with autopilot
`$_COPILOT_CMD = "$copilotCmd"
function copilot { & `$_COPILOT_CMD --agent oh-my-copilot:atlas --autopilot @args }
Set-Alias cop copilot
Set-Alias atlas copilot
"@
    Add-Content -Path $profilePath -Value $block
    Write-Host "✅ Profile updated. Run '. `$PROFILE' or open a new terminal."
} else {
    Write-Host "✅ Already configured. 'copilot', 'atlas', and 'cop' already run as Atlas."
}
```

4. Verify by reloading the profile and confirming aliases:

```powershell
. $PROFILE
Get-Alias atlas, cop -ErrorAction SilentlyContinue
```

## After setup

- `copilot` → Atlas + autopilot
- `atlas`   → Atlas + autopilot  
- `cop`     → Atlas + autopilot

To undo, remove the `oh-my-copilot:` block from `$PROFILE`.
