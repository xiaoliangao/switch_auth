---
name: openclaw-auth-switch
description: "Manage and switch between multiple OpenClaw auth profiles (e.g., OpenAI Codex OAuth accounts). Use this skill whenever the user mentions switching OpenClaw accounts, managing auth profiles, toggling between OpenAI/Codex logins, or having multiple OpenClaw identities. Also trigger when the user says things like 'switch to my other account', 'log in with my team account', 'use my personal OpenClaw auth', 'I have two OpenAI accounts', or asks about openclaw auth-profiles.json. Trigger even for tangential mentions like 'my other Codex login' or 'switch provider credentials'."
---

# OpenClaw Auth Profile Switcher

This skill helps users manage multiple OpenClaw auth profiles — for example, switching between a personal and a team OpenAI Codex account without re-running the full OAuth login flow each time.

## How It Works

OpenClaw stores OAuth credentials (access token, refresh token, accountId, expiry) in:

```
~/.openclaw/agents/<agentId>/agent/auth-profiles.json
```

Switching accounts = swapping this file. The bundled script automates this by:

1. Backing up each account's `auth-profiles.json` to `~/.openclaw-auth-profiles/<label>.json`
2. Tracking which label is currently active
3. On switch: auto-saving the current profile, then restoring the target one

## Usage

Run the bundled script at `scripts/switch-openclaw-auth.sh`.

### First-Time Setup

For each account the user wants to manage:

```bash
# Step 1: Log in as the first account via OpenClaw, then save it
openclaw models auth login --provider openai-codex
bash <skill-path>/scripts/switch-openclaw-auth.sh save <label-a>

# Step 2: Log in as the second account, then save it
openclaw models auth login --provider openai-codex
bash <skill-path>/scripts/switch-openclaw-auth.sh save <label-b>
```

Or use the combined `login` command which runs `openclaw models auth login` and saves in one step:

```bash
bash <skill-path>/scripts/switch-openclaw-auth.sh login <label>
```

### Switching

```bash
bash <skill-path>/scripts/switch-openclaw-auth.sh switch <label>
```

This auto-saves the current account before overwriting, so no credentials are lost.

### Checking Status

```bash
bash <skill-path>/scripts/switch-openclaw-auth.sh status
```

Shows the active label, saved accounts, and their accountIds.

## Commands Reference

| Command | Args | Description |
|---------|------|-------------|
| `save`   | `<label>` | Save the current auth-profiles.json under the given label |
| `switch` | `<label>` | Switch to a previously saved label (auto-saves current first) |
| `login`  | `<label>` | Run `openclaw models auth login --provider openai-codex` then save |
| `status` | — | Show current label and all saved accounts |

## Customization

Labels are arbitrary strings — users can pick whatever makes sense: `personal` / `team`, `account-a` / `account-b`, `work` / `side-project`, etc.

Default backup location is `~/.openclaw-auth-profiles/`. This can be changed by editing the `BACKUP_DIR` variable in the script.

## Important Notes

- **Token sink risk**: If the user logs into the same OpenAI account from multiple tools (OpenClaw, Codex CLI, etc.), refresh tokens may invalidate each other. This script can't prevent that — it only manages the local file.
- **The script auto-detects** the `auth-profiles.json` location by searching `~/.openclaw/`. If OpenClaw's directory structure changes, the `find` fallback handles most cases.
- **No sensitive data is logged or printed** beyond the accountId field (which is an opaque identifier, not a secret).

## When to Run the Script for the User

If the user asks to switch accounts, run the script directly:

```bash
bash /path/to/this/skill/scripts/switch-openclaw-auth.sh switch <label>
```

If the user hasn't set up profiles yet, walk them through the first-time setup flow above. Confirm which labels they want to use before proceeding.
