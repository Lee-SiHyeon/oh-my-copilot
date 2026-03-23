---
name: dev-browser
description: "Browser automation with persistent page state. Use when asked to navigate websites, fill forms, take screenshots, extract web data, test web apps, or automate browser workflows. Trigger: 'go to [url]', 'click on', 'fill out the form', 'take a screenshot', 'scrape', 'automate', 'test the website'. (dev-browser - oh-my-opencode port)"
allowed-tools:
  - Bash
  - Read
---

# Dev Browser Skill

Browser automation that maintains page state across script executions. Write small, focused scripts to accomplish tasks incrementally.

---

## Approach Selection

- **Local/source-available sites**: Read the source code first to write selectors directly
- **Unknown page layouts**: Use `getAISnapshot()` to discover elements and `selectSnapshotRef()` to interact
- **Visual feedback**: Take screenshots to see what the user sees

---

## Setup

Ensure the dev-browser server is running first.

Start the dev-browser server:
```bash
./skills/dev-browser/server.sh &
```

Wait for `Ready` message before running scripts.

---

## Writing Scripts

Run from `skills/dev-browser/` directory.

```bash
cd skills/dev-browser && npx tsx <<'EOF'
import { connect, waitForPageLoad } from "@/client.js";
const client = await connect();
const page = await client.page("example", { viewport: { width: 1920, height: 1080 } });
await page.goto("https://example.com");
await waitForPageLoad(page);
console.log({ title: await page.title(), url: page.url() });
await client.disconnect();
EOF
```

---

## Key Principles

1. **Small scripts**: Each script does ONE thing (navigate, click, fill, check)
2. **Evaluate state**: Log/return state at end to decide next steps
3. **Descriptive page names**: `"checkout"`, `"login"`, not `"main"`
4. **Disconnect to exit**: `await client.disconnect()` — pages persist on server
5. **Plain JS in evaluate**: `page.evaluate()` runs in browser — no TypeScript syntax

---

## Workflow Loop

1. Write a script for ONE action
2. Run it and observe output
3. Evaluate — did it work? What's the current state?
4. Decide — done or need another script?
5. Repeat until task is done

---

## Client API

```typescript
const client = await connect();
const page = await client.page("name");
const pages = await client.list();
await client.close("name");
await client.disconnect();  // pages persist

// ARIA Snapshot
const snapshot = await client.getAISnapshot("name");
const element = await client.selectSnapshotRef("name", "e5");
```

## Screenshots

```typescript
await page.screenshot({ path: "tmp/screenshot.png" });
await page.screenshot({ path: "tmp/full.png", fullPage: true });
```

## Waiting

```typescript
import { waitForPageLoad } from "@/client.js";
await waitForPageLoad(page);
await page.waitForSelector(".results");
await page.waitForURL("**/success");
```

## ARIA Snapshot (Element Discovery)

Returns YAML accessibility tree with refs:
```yaml
- banner:
  - link "Homepage" [ref=e1]
- main:
  - button "Submit" [ref=e5]
```

Interact: `const el = await client.selectSnapshotRef("page", "e5"); await el.click();`
