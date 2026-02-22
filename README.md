# Agent Voice Hooks

<div align="center">
  <img src="logo.png" width="300" alt="Agent Voice Hooks Logo">
</div>

> **Bring voice notifications to your AI coding assistant** — get real-time voice announcements when tasks complete, permissions are needed, or your agent is waiting for you. Works with **Claude Code** and **Kimi Code CLI**.

---

## Why Voice Hooks?

AI coding assistants are powerful, but keeping your eyes glued to the terminal isn't always practical. Voice hooks transform your AI agent into an active collaborator that speaks up when it needs you—so you can grab a coffee, switch contexts, or work on something else while your agent handles the heavy lifting.

**Perfect for:**
- Long-running tasks (tests, builds, deploys)
- Multitasking across projects
- Accessibility and screen-free workflows
- Keeping collaborators informed in pair programming sessions

---

## Supported Agents

| Agent | Integration Type | Setup |
|-------|-----------------|-------|
| **Claude Code** | Native hooks (`settings.json`) | Copy scripts to `~/.claude/`
| **Kimi Code CLI** | Bridge wrapper (`kimi-voice`) | Use `kimi-voice` command |

Both agents share the same **VoiceMode MCP** for high-quality text-to-speech.

---

## What You'll Hear

| Event | Voice Announcement | Example |
|-------|-------------------|---------|
| **Task completed** | "Done: [summary]" | "Done: Refactored the authentication module" |
| **Permission needed** | "Waiting for permission to [action]" | "Waiting for permission to run tests" |
| **Idle timeout** | "Agent is waiting for your next instruction" | After 60 seconds of inactivity |

---

## Quick Start

### Claude Code

```bash
# Clone the repository
git clone https://github.com/yourusername/agent-voice-hooks.git
cd agent-voice-hooks

# Install Claude hooks
./install.sh --claude
```

### Kimi Code CLI

```bash
# One-command install
curl -fsSL https://raw.githubusercontent.com/yourusername/agent-voice-hooks/main/install.sh | bash

# Or clone and install manually:
git clone https://github.com/yourusername/agent-voice-hooks.git
cd agent-voice-hooks
./install.sh --kimi
```

### Usage with Kimi

Replace `kimi` with `kimi-voice`:

```bash
# Instead of:
kimi "help me refactor this code"

# Use:
kimi-voice "help me refactor this code"
```

All arguments are passed through to Kimi:

```bash
kimi-voice --model kimi-k2 "explain this function"
kimi-voice --help
```

### Optional: VoiceMode MCP

For model-driven announcements (your agent proactively speaking), register the voicemode MCP:

```bash
# This is done automatically by install.sh, but you can also do it manually:
# For Claude:
claude mcp add voicemode -- uvx --refresh voice-mode

# For Kimi:
kimi mcp add voicemode -- uvx --refresh voice-mode
```

Then activate the skill:

```
/skill:voice-announce
```

---

## How It Works

### Claude Code (Native Hooks)

Claude Code supports native hooks via `settings.json`. Agent Voice Hooks provide pre-configured scripts that Claude calls automatically:

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Claude    │────▶│   Hooks     │────▶│   Voice     │
│    Code     │     │  (scripts)  │     │   (TTS)     │
└─────────────┘     └─────────────┘     └─────────────┘
```

### Kimi Code CLI (Bridge)

Kimi Voice Hooks use Kimi's **Wire protocol** (`kimi --wire`) to intercept events and trigger voice announcements:

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Terminal  │────▶│ kimi-voice  │────▶│ kimi --wire │
│   (stdin)   │     │  (bridge)   │     │   (Kimi)    │
└─────────────┘     └──────┬──────┘     └─────────────┘
                           │
                           ▼
                    ┌─────────────┐
                    │   Voice     │
                    │  (TTS)      │
                    └─────────────┘
```

The bridge transparently proxies all communication while intercepting:
- **TurnEnd** events → Announce task completion
- **ApprovalRequest** events → Announce permission needs
- **Idle timer** → Announce when waiting for input

---

## Configuration

### Global Config

Edit `~/.config/kimi-voice/config.toml`:

```toml
[voice]
backend = "voicemode"  # "voicemode", "say", or "silent"
voice = "af_sky"       # Voice identifier
speed = 1.0            # Speech rate

[idle]
timeout = 60           # Seconds before idle announcement
enabled = true

[events]
announce_turn_end = true
announce_approval = true
announce_idle = true
announce_errors = false
```

### Project Config

Create `.kimi-voice.toml` in your project directory to override global settings:

```toml
[voice]
voice = "am_adam"  # Use male voice for this project
speed = 1.2          # Slightly faster

[idle]
timeout = 30         # Shorter idle timeout
```

### Simple Voice Override

Create a `.voice` file with just the voice name (compatible with both Claude and Kimi voice hooks):

```bash
echo "am_adam" > .voice
```

### Environment Variables

Override any setting via environment:

```bash
export KIMI_VOICE_VOICE="af_nicole"
export KIMI_VOICE_SPEED="1.5"
export KIMI_VOICE_IDLE_TIMEOUT="30"
```

---

## Voice Backends

### VoiceMode (Recommended)

High-quality TTS with Kokoro and OpenAI voices:

```bash
# Install
uvx voice-mode-install

# Available voices
voicemode voices list
```

**Popular voices:** `af_sky`, `af_nicole`, `af_bella`, `am_adam`, `am_echo`

### macOS `say` (Built-in)

Zero-dependency fallback for macOS:

```toml
[voice]
backend = "say"
voice = "Samantha"
```

**Available voices:** `say -v '?'`

### Silent Mode

Logs to stderr without producing audio (useful for CI):

```toml
[voice]
backend = "silent"
```

---

## MCP Skill: voice-announce

The voice-announce skill instructs your agent to proactively use the voicemode tool:

```
/skill:voice-announce
```

**When your agent will speak:**
- After completing significant tasks
- Before asking questions with multiple options
- When errors require user guidance
- When long-running operations complete

The bridge/hooks handle the basic events automatically; the skill adds conversational context.

---

## Comparison: Claude vs Kimi

| Feature | Claude Code | Kimi Code CLI |
|---------|-------------|---------------|
| Integration | Native hooks (`settings.json`) | Bridge wrapper (`kimi-voice`) |
| Event types | Stop, Notification | Wire protocol events |
| Installation | Copy scripts | One-command install |
| Idle timeout | Native | Bridge timer |
| Permission prompts | Native | Intercepted from wire |
| MCP support | Yes | Yes (shared voicemode) |
| `.voice` file | Yes | Yes (compatible) |

**Key difference:** Claude has native hook support; Kimi requires the `kimi-voice` bridge wrapper to intercept Wire protocol events.

---

## Requirements

- **Python** 3.10+
- **Claude Code** (`claude`) or **Kimi Code CLI** (`kimi`)
- **macOS** or **Linux**
- **VoiceMode** (optional but recommended)

---

## Troubleshooting

See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) for detailed solutions to common issues.

Quick checks:

```bash
# Verify installation
~/.local/share/kimi-voice/kimi-voice --version

# Test voice output
~/.local/share/kimi-voice/kimi-voice --help  # Should show help

# Check MCP registration
# For Claude:
cat ~/.claude/mcp.json | grep voicemode
# For Kimi:
cat ~/.kimi/mcp.json | grep voicemode

# Debug mode
KIMI_VOICE_DEBUG=1 kimi-voice "test"
```

---

## Development

See [AGENT-SETUP.md](./AGENT-SETUP.md) for development setup and contribution guidelines.

---

## License

MIT — feel free to use, modify, and distribute.

---

## About

Built to make AI coding assistants feel more like pair programmers. Works with Claude Code and Kimi Code CLI. Contributions welcome!
