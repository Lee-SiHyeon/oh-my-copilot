# Runtime learnings moved to user-local state

`LEARNINGS.md` is no longer mutable runtime state in the plugin root.

- Canonical runtime learnings: `~/.copilot/oh-my-copilot/LEARNINGS.md`
- Canonical runtime DB: `~/.copilot/oh-my-copilot/omc-memory.db`
- Shared plugin root: code and docs only

On upgrade, omc lazily migrates legacy plugin-root runtime files into `~/.copilot/oh-my-copilot/` the first time user-local state is missing. Once the user-local files exist, they always win.
