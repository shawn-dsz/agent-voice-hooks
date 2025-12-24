# Claude Voice Notification Hooks

> **Turn Claude into a vocal collaborator** — get real-time voice announcements when tasks complete, permissions are needed, or your agent is waiting for you.

---

## Why Voice Hooks?

Claude Code is powerful, but keeping your eyes glued to the terminal isn't always practical. Voice hooks transform your AI agent into an active collaborator that speaks up when it needs you—so you can grab a coffee, switch contexts, or work on something else while Claude handles the heavy lifting.

**Perfect for:**
- Long-running tasks (tests, builds, deploys)
- Multitasking across projects
- Accessibility and screen-free workflows
- Keeping collaborators informed in pair programming sessions

---

## What You'll Hear

| Event | Voice Announcement | Example |
|-------|-------------------|---------|
| **Task completed** | "Done: [summary]" | "Done: Built and tested the application" |
| **Waiting for input** | "Claude is waiting for your input" | After 60 seconds of idle time |
| **Permission needed** | "Claude is waiting to [action]" | "Claude is waiting to Run hook installation test" |

> **Smart Context**: Permission announcements automatically extract what Claude is actually trying to do—so you hear the action, not just the tool name.

---

## Quick Start

### Step 1: Install VoiceMode (one-time, global)

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
uvx voice-mode-install
claude mcp add --scope user voicemode -- uvx --refresh voice-mode
```

*VoiceMode is the voice engine that powers these hooks. You only need to install it once.*

### Step 2: Install the Hooks Globally

Copy the hooks and settings to your global Claude configuration:

```bash
# Copy the hooks folder
cp -r .claude/hooks ~/.claude/

# Merge settings.json into your global config
cat .claude/settings.json >> ~/.claude/settings.json
```

*This enables voice notifications for **all** your Claude Code projects automatically.*

### Step 3: Test It

```bash
~/.claude/hooks/test-hooks.sh
```

You should hear voice confirmations for each event type.

---

## How It Works

These hooks use Claude Code's native hook system to listen for events and trigger voice announcements via VoiceMode:

| Hook File | Trigger | What It Does |
|-----------|---------|--------------|
| `permission-request.sh` | Permission dialog shown | Announces what Claude is waiting to do |
| `task-summary.sh` | Task completes | Reads the task summary aloud |
| `notification-idle.sh` | Idle for 60+ seconds | Reminds you that Claude is waiting |

All hooks are configured in `~/.claude/settings.json` using the `Notification` and `Stop` event types.

---

## Customization

Want to change the voice, speed, or message format? Edit the hook scripts directly:

```bash
~/.claude/hooks/permission-request.sh
~/.claude/hooks/task-summary.sh
~/.claude/hooks/notification-idle.sh
```

Each script calls `voicemode converse` with custom messages. See [VoiceMode docs](https://github.com/your-repo/voicemode) for available options.

---

## Requirements

- **Claude Code** (latest version)
- **VoiceMode** MCP server (installed above)
- macOS or Linux

---

## License

MIT — feel free to use, modify, and distribute.

---

## About

Built to make Claude Code feel more like a pair programmer and less like a headless CLI. Contributions welcome!
