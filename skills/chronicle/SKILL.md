---
name: chronicle
version: 1.0.0
description: |
  Copilot CLI session history and self-improvement. 
  Use /chronicle to generate standup reports, personalized tips, and improve custom instructions.
  Trigger: "chronicle", "standup", "session history", "improve instructions"
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
---

# CHRONICLE — Session History & Self-Improvement

> Note: /chronicle requires experimental features. Run `/experimental on` first.

## Available Commands

### Standup Report
```
/chronicle standup
```
Generates a short report from the last 24 hours of CLI sessions:
- Branch names you worked on
- What was accomplished
- GitHub PR links and their status
- Grouped by completion status (✅ Done / �� In Progress)

Customize with:
```
/chronicle standup since yesterday 9am
/chronicle standup for the last week
```

### Personalized Tips
```
/chronicle tips
```
Analyzes your session patterns and provides personalized tips for using Copilot CLI more effectively. Based on your actual usage history.

### Improve Custom Instructions
```
/chronicle improve
```
**Most powerful feature**: Analyzes your session history to find patterns where:
- Copilot misunderstood your intent
- There was excessive back-and-forth  
- You had to repeat the same corrections

Then generates updated instructions for `~/.copilot/copilot-instructions.md` or `.github/copilot-instructions.md`.

**Run this after every major project** to continuously improve your Copilot experience.

### Rebuild Session Index
```
/chronicle reindex
```
If chronicle seems to have stale data, rebuild the index from session history files.

---

## Session Management

### Resume previous sessions
```bash
copilot --continue          # Resume most recent session
copilot --resume            # Pick from list of recent sessions
copilot --resume SESSION-ID # Jump to specific session
```

During a session:
```
/resume             # Pick from recent sessions
/resume SESSION-ID  # Jump to specific session
/rename My Task     # Rename current session for easy finding
```

### Share a session
```
/share gist         # Save as private GitHub gist (shareable URL)
/share file PATH    # Save as Markdown file
```

### Session data location
```
~/.copilot/session-state/{session-id}/
├── events.jsonl     # Full session history
├── workspace.yaml   # Metadata  
├── plan.md          # Implementation plan
├── checkpoints/     # Compaction history
└── files/           # Persistent artifacts
```

---

## Self-Improvement Workflow

Best practice — run weekly:

```
1. /experimental on           # Enable chronicle
2. /chronicle improve         # Get instruction improvements
3. Review suggestions
4. Apply to ~/.copilot/copilot-instructions.md
5. (Optional) git add + commit to project
```

This creates a feedback loop that makes Copilot progressively more useful for your specific workflow.

---

## /research Command (Deep Web Search)

Different from asking Copilot a question — produces a full Markdown report:

```
/research How does React implement concurrent rendering?
/research What are the best patterns for error handling in TypeScript?
/research How is feature X implemented in this codebase?
```

After research completes:
```
Ctrl+Y              # Open report in editor
/share gist research # Share as GitHub gist
/share file research PATH  # Save to file
```

The research agent searches: web + GitHub repos + your local codebase.
