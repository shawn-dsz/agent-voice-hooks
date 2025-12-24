# Claude Voice Notification Hooks

Get voice announcements when Claude completes tasks, needs permission, or is waiting for input.

## Tell Your Agent To Do This:

**Step 1: Install VoiceMode** (one time only - this works for all projects)

Run these commands:
```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
uvx voice-mode-install
claude mcp add --scope user voicemode -- uvx --refresh voice-mode
```

**Step 2: Install the hooks globally**

Copy the `.claude` folder to your global Claude config:
```bash
cp -r .claude ~/.claude/
```

**Step 3: Test it**

```bash
~/.claude/hooks/test-hooks.sh
```

That's it! Now voice notifications will work for every project automatically.

## What You'll Hear

| Event | Voice Announcement |
|-------|-------------------|
| Task completed | "Done: [summary]" |
| Idle (60s+) | "Claude is waiting for your input" |
| Permission needed | "Claude needs permission to use [tool]" |

MIT License
