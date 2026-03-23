---
name: setup
description: Configure shell profile so that `copilot`, `atlas`, and `cop` commands always launch with --agent oh-my-copilot:atlas --autopilot. Run this once after installing oh-my-copilot.
---

# oh-my-copilot Setup

Configure the user's shell profile to always launch Copilot CLI as Atlas with autopilot enabled.

## Steps

1. Find the real `copilot` path in npm bin:

```bash
COPILOT_BIN="$(npm root -g 2>/dev/null | xargs -I{} dirname {})/copilot"
if [ ! -x "$COPILOT_BIN" ]; then
  COPILOT_BIN="$(command -v copilot 2>/dev/null)"
fi
echo "Found copilot at: $COPILOT_BIN"
```

2. Detect and check the shell profile:

```bash
if [ -f "$HOME/.zshrc" ]; then
  PROFILE="$HOME/.zshrc"
elif [ -f "$HOME/.bashrc" ]; then
  PROFILE="$HOME/.bashrc"
else
  PROFILE="$HOME/.bash_profile"
fi
ALREADY_CONFIGURED=$(grep -l "oh-my-copilot:atlas" "$PROFILE" 2>/dev/null)
echo "Profile: $PROFILE"
```

3. If not already configured, append the atlas wrapper to the profile:

```bash
if [ -z "$ALREADY_CONFIGURED" ]; then
  cat >> "$PROFILE" << 'ENDOFBLOCK'

# oh-my-copilot: always launch Copilot CLI as Atlas with autopilot
_COPILOT_BIN="$(npm root -g 2>/dev/null | xargs -I{} dirname {})/copilot"
[ -x "$_COPILOT_BIN" ] || _COPILOT_BIN="$(command -v copilot)"
copilot() { "$_COPILOT_BIN" --agent oh-my-copilot:atlas --autopilot "$@"; }
alias cop=copilot
alias atlas=copilot
ENDOFBLOCK
  echo "✅ Profile updated. Run 'source $PROFILE' or open a new terminal."
else
  echo "✅ Already configured. 'copilot', 'atlas', and 'cop' already run as Atlas."
fi
```

4. Verify by reloading the profile and confirming aliases:

```bash
source "$PROFILE"
type atlas cop 2>/dev/null
```

## After setup

- `copilot` → Atlas + autopilot
- `atlas`   → Atlas + autopilot
- `cop`     → Atlas + autopilot

To undo, remove the `# oh-my-copilot:` block from `$PROFILE`.
