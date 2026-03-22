---
name: playwright
description: "MUST USE for any browser-related tasks. Browser automation via agent-browser CLI - verification, browsing, information gathering, web scraping, testing, screenshots, and all browser interactions. (playwright - oh-my-opencode port)"
allowed-tools:
  - Execute
---

# Browser Automation with agent-browser

## Quick Start

```bash
agent-browser open <url>        # Navigate to page
agent-browser snapshot -i       # Get interactive elements with refs
agent-browser click @e1         # Click element by ref
agent-browser fill @e2 "text"   # Fill input by ref
agent-browser close             # Close browser
```

## Core Workflow

1. Navigate: `agent-browser open <url>`
2. Snapshot: `agent-browser snapshot -i` (returns elements with refs like `@e1`, `@e2`)
3. Interact using refs from the snapshot
4. Re-snapshot after navigation or significant DOM changes

---

## Commands

### Navigation
```bash
agent-browser open <url>
agent-browser back
agent-browser forward
agent-browser reload
agent-browser close
```

### Snapshot
```bash
agent-browser snapshot            # Full accessibility tree
agent-browser snapshot -i         # Interactive elements only (recommended)
agent-browser snapshot -c         # Compact output
agent-browser snapshot -d 3       # Limit depth to 3
agent-browser snapshot -s "#main" # Scope to CSS selector
```

### Interactions (use @refs from snapshot)
```bash
agent-browser click @e1
agent-browser dblclick @e1
agent-browser fill @e2 "text"     # Clear and type
agent-browser type @e2 "text"     # Type without clearing
agent-browser press Enter
agent-browser press Control+a
agent-browser hover @e1
agent-browser check @e1
agent-browser select @e1 "value"
agent-browser scroll down 500
agent-browser drag @e1 @e2
agent-browser upload @e1 file.pdf
```

### Get Information
```bash
agent-browser get text @e1
agent-browser get html @e1
agent-browser get value @e1
agent-browser get attr @e1 href
agent-browser get title
agent-browser get url
agent-browser get count ".item"
```

### Screenshots & PDF
```bash
agent-browser screenshot
agent-browser screenshot path.png
agent-browser screenshot --full
agent-browser pdf output.pdf
```

### Wait
```bash
agent-browser wait @e1
agent-browser wait 2000
agent-browser wait --text "Success"
agent-browser wait --url "**/dashboard"
agent-browser wait --load networkidle
```

### Cookies & Storage
```bash
agent-browser cookies
agent-browser cookies set name value
agent-browser cookies clear
agent-browser storage local
agent-browser storage local set k v
```

### Network
```bash
agent-browser network route <url>
agent-browser network route <url> --abort
agent-browser network route <url> --body '{}'
agent-browser network requests
```

### Tabs
```bash
agent-browser tab
agent-browser tab new [url]
agent-browser tab 2
agent-browser tab close
```

### JavaScript
```bash
agent-browser eval "document.title"
```

---

## Global Options

| Option | Description |
|--------|-------------|
| `--session <name>` | Isolated browser session |
| `--profile <path>` | Persistent browser profile |
| `--headed` | Show browser window |
| `--cdp <port>` | Connect via Chrome DevTools Protocol |
| `--json` | Machine-readable JSON output |

---

## Example: Form Submission

```bash
agent-browser open https://example.com/form
agent-browser snapshot -i
# Shows: textbox "Email" [ref=e1], textbox "Password" [ref=e2], button "Submit" [ref=e3]

agent-browser fill @e1 "user@example.com"
agent-browser fill @e2 "password123"
agent-browser click @e3
agent-browser wait --load networkidle
agent-browser snapshot -i  # Check result
```

## Example: Authentication with Saved State

```bash
# Login once
agent-browser open https://app.example.com/login
agent-browser fill @e1 "username"
agent-browser fill @e2 "password"
agent-browser click @e3
agent-browser wait --url "**/dashboard"
agent-browser state save auth.json

# Later sessions
agent-browser state load auth.json
agent-browser open https://app.example.com/dashboard
```

---

Install: `bun add -g agent-browser && agent-browser install`
