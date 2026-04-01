# Security Policy

## Supported Versions

| Version | Supported          |
|---------|--------------------|
| 2.2.x   | ✅ Actively supported |
| < 2.2   | ❌ No security patches |

## Reporting a Vulnerability

If you discover a security vulnerability in oh-my-copilot, please report it responsibly:

1. **GitHub Security Advisory** (Preferred): Go to [Security Advisories](https://github.com/Lee-SiHyeon/oh-my-copilot/security/advisories/new) and create a new advisory.
2. **Email**: Contact the maintainer directly via GitHub profile.

**Please do NOT open a public issue for security vulnerabilities.**

### What to Include
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

### Response Timeline
- **Acknowledgment**: Within 48 hours
- **Assessment**: Within 1 week
- **Fix**: Depending on severity, typically within 2 weeks

## Scope

### In Scope
- Shell hook scripts (`scripts/*.sh`, `scripts/*.ps1`)
- Agent prompt definitions (`agents/*.agent.md`)
- SQLite database operations (`init-memory.sh`, `consolidate.sh`)
- Permission cache and danger pattern detection (`pre-tool-use.sh`)
- Plugin installation and update mechanisms

### Out of Scope
- GitHub Copilot CLI itself (report to [GitHub](https://github.com/github/copilot-cli))
- Language model behavior or outputs
- Third-party MCP servers
- User-local state files (`~/.copilot/oh-my-copilot/`)

## Security Measures

oh-my-copilot implements several security measures:

- **Danger Pattern Detection**: `pre-tool-use.sh` blocks destructive commands (`rm -rf`, `git push --force`, `DROP TABLE`, `format-volume`) with a user confirmation prompt
- **Permission Cache**: 7-day TTL with MD5 hash keys; destructive operations excluded from caching
- **Meta Policy Rules**: SQLite-stored domain-based constraints (e.g., force push requires confirmation)
- **Agent Model Guardrails**: Prevents unauthorized model escalation (e.g., Opus rejection policy)
- **README Sync Guard**: Blocks commits to shared code paths without README.md updates
