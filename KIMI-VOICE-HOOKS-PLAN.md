# Kimi Code CLI Voice Hooks: Implementation Plan

> Bring the same voice notification experience from Claude Code to Kimi Code CLI.
> This plan is designed to be handed to an agent (KME) for implementation.

---

## Background

Claude Code has native lifecycle hooks (Stop, Notification) that fire shell commands on events like task completion, idle timeout, and permission requests. Kimi Code CLI has **no equivalent hook system**. Instead, it offers:

1. **Wire Mode** (`kimi --wire`): A JSON-RPC 2.0 protocol over stdin/stdout that emits structured events (`TurnEnd`, `ApprovalRequest`, `StatusUpdate`, etc.)
2. **MCP Support**: Register external tool servers via `~/.kimi/mcp.json`
3. **Agent Skills**: Markdown-based prompt templates in `.agents/skills/` that instruct the model to follow specific behaviours

The implementation uses all three mechanisms in a layered approach.

---

## Architecture Overview

```
                    ┌──────────────────────────────────────────────┐
                    │              User's Terminal                 │
                    │                                              │
                    │   $ kimi-voice "help me refactor auth"       │
                    │                                              │
                    └───────────────────┬──────────────────────────┘
                                        │
                                        ▼
                    ┌──────────────────────────────────────────────┐
                    │          kimi-voice (Bridge Script)          │
                    │                                              │
                    │  - Launches `kimi --wire`                    │
                    │  - Proxies stdin/stdout between user & Kimi  │
                    │  - Intercepts Wire events:                   │
                    │     • TurnEnd → voice: task completion       │
                    │     • ApprovalRequest → voice: permission    │
                    │     • Idle timer → voice: waiting for input  │
                    │  - Responds to ApprovalRequests by           │
                    │    forwarding to user terminal                │
                    │                                              │
                    └──────────┬───────────────┬───────────────────┘
                               │               │
                    ┌──────────▼───┐   ┌───────▼──────────────────┐
                    │  kimi --wire │   │  Voice Output            │
                    │  (Kimi CLI)  │   │  (voicemode / say / etc) │
                    └──────────────┘   └──────────────────────────┘
                               │
                    ┌──────────▼──────────────────────────────────┐
                    │          MCP: voicemode                      │
                    │  (Registered in ~/.kimi/mcp.json)           │
                    │  Kimi can call this proactively for         │
                    │  model-driven announcements                 │
                    └─────────────────────────────────────────────┘
```

**Two layers:**

| Layer | Mechanism | Covers |
|-------|-----------|--------|
| **Wire Bridge** (passive) | Intercepts Wire protocol events | Task completion, permission requests, idle detection |
| **MCP + Skill** (active) | Model calls voicemode tool voluntarily | Conversational announcements, question context, custom messages |

---

## Directory Structure

```
kimi-voice-hooks/
├── PLAN.md                          # This file
├── README.md                        # User-facing documentation
├── install.sh                       # One-command installer
│
├── bridge/
│   ├── kimi-voice                   # Main bridge script (Python)
│   ├── requirements.txt             # Dependencies (minimal)
│   ├── bridge.py                    # Core Wire protocol handler
│   ├── events.py                    # Event type definitions & handlers
│   ├── voice.py                     # Voice output abstraction
│   ├── idle_tracker.py              # Idle timer logic
│   └── config.py                    # Configuration loading
│
├── mcp/
│   └── mcp-config.json              # MCP registration snippet for voicemode
│
├── skills/
│   └── voice-announce/
│       └── SKILL.md                 # Skill instructing Kimi to use voicemode
│
├── config/
│   ├── kimi-voice.toml              # Default configuration
│   └── voices.toml                  # Voice presets and aliases
│
└── tests/
    ├── test-bridge.sh               # Integration test for bridge
    ├── test-voice.sh                # Voice output test
    ├── test_events.py               # Unit tests for event handling
    └── mock-wire-server.py          # Mock Kimi Wire server for testing
```

---

## Component Specifications

### Component 1: Wire Bridge (`bridge/`)

**Purpose:** Launch `kimi --wire`, proxy all communication between the user and Kimi, and intercept specific events to trigger voice announcements.

**Language:** Python 3.10+ (async, using `asyncio` for concurrent stdin/stdout handling)

**Why Python:** Kimi CLI is Python-based, the project already uses Python for JSON processing in existing hooks, and `asyncio` handles the bidirectional streaming cleanly.

#### 1.1 Entry Point: `kimi-voice`

A shell wrapper that:
1. Checks dependencies (Python 3.10+, voicemode or `say`)
2. Activates the bridge
3. Passes all arguments through to `kimi --wire`

```bash
#!/usr/bin/env bash
# kimi-voice - Voice-enabled Kimi Code CLI wrapper
exec python3 "$(dirname "$0")/bridge.py" "$@"
```

Installed to `~/.local/bin/kimi-voice` or similar PATH location.

#### 1.2 Core Bridge: `bridge.py`

Responsibilities:
- Spawn `kimi --wire` as a subprocess
- Read JSON-RPC messages from Kimi's stdout (line-delimited JSON)
- Forward user input from terminal stdin to Kimi's stdin
- Intercept and react to specific event types
- Handle the `initialize` handshake (protocol version negotiation)

Key design decisions:
- **Non-blocking I/O**: Use `asyncio.create_subprocess_exec` with `PIPE` for stdin/stdout
- **Message routing**: Parse each JSON-RPC message, check `method` field, dispatch to handlers, then forward to terminal
- **Transparent proxy**: The user should not notice any difference from running `kimi` directly, except they hear voice announcements

```python
# Pseudocode structure
async def main():
    proc = await asyncio.create_subprocess_exec(
        "kimi", "--wire", *sys.argv[1:],
        stdin=PIPE, stdout=PIPE, stderr=PIPE
    )

    # Three concurrent tasks:
    # 1. Read from terminal stdin, forward to kimi stdin
    # 2. Read from kimi stdout, intercept events, forward to terminal
    # 3. Idle timer that fires after configured timeout
    await asyncio.gather(
        forward_user_input(proc.stdin),
        process_kimi_output(proc.stdout),
        idle_monitor()
    )
```

#### 1.3 Event Handlers: `events.py`

Each Wire event type maps to a handler function:

| Wire Event | Handler | Voice Action |
|------------|---------|--------------|
| `TurnEnd` | `on_turn_end()` | Announce task summary. Extract last `ContentPart` text, summarise to ~10 words, speak it. |
| `ApprovalRequest` | `on_approval_request()` | Announce what permission is needed. Extract `action` field, clean up, speak "Waiting for permission to {action}". |
| `TurnBegin` | `on_turn_begin()` | Reset idle timer. No voice action. |
| `StepInterrupted` | `on_step_interrupted()` | Announce interruption if unexpected. |
| `ContentPart` | `on_content_part()` | Accumulate text for turn summary. No immediate voice action. |
| `ToolCall` | `on_tool_call()` | Track tool calls for context (e.g., which files were edited). |

**TurnEnd handler detail:**

```python
async def on_turn_end(accumulated_content: list[str], config: Config):
    """Announce task completion summary."""
    if not accumulated_content:
        await speak("Task completed. Ready for next instructions.", config)
        return

    # Take last content block, truncate to ~10 words
    last_content = accumulated_content[-1]
    words = last_content.split()
    summary = " ".join(words[:10])
    if len(words) > 10:
        summary += "..."

    await speak(f"Done: {summary}", config)
```

**ApprovalRequest handler detail:**

```python
async def on_approval_request(payload: dict, config: Config):
    """Announce permission request."""
    action = payload.get("action", "")
    sender = payload.get("sender", "")

    if action:
        # Clean up common prefixes
        clean = re.sub(r"^(run shell command|execute):\s*", "", action, flags=re.I)
        msg = f"Waiting for permission to {clean}"
    elif sender:
        msg = f"Waiting for permission from {sender}"
    else:
        msg = "Waiting for your permission"

    await speak(msg, config)
```

#### 1.4 Idle Tracker: `idle_tracker.py`

```python
class IdleTracker:
    def __init__(self, timeout_seconds: int = 60):
        self.timeout = timeout_seconds
        self._last_activity = time.monotonic()
        self._announced = False

    def reset(self):
        self._last_activity = time.monotonic()
        self._announced = False

    async def monitor(self, speak_fn, config):
        while True:
            await asyncio.sleep(5)  # Check every 5 seconds
            elapsed = time.monotonic() - self._last_activity
            if elapsed >= self.timeout and not self._announced:
                await speak_fn("Kimi is waiting for your next instruction", config)
                self._announced = True
```

Reset on:
- `TurnBegin` (user sent input)
- `TurnEnd` (Kimi finished, user needs to respond)
- Any user stdin activity

#### 1.5 Voice Output: `voice.py`

Abstraction layer supporting multiple TTS backends:

```python
async def speak(message: str, config: Config):
    """Speak a message using the configured TTS backend."""
    backend = config.tts_backend  # "voicemode" | "say" | "kokoro" | "openai"

    if backend == "voicemode":
        await _speak_voicemode(message, config.voice, config.speed)
    elif backend == "say":
        await _speak_macos_say(message, config.voice)
    elif backend == "kokoro":
        await _speak_kokoro(message, config.voice, config.speed)
    elif backend == "openai":
        await _speak_openai(message, config.voice)

async def _speak_voicemode(message: str, voice: str, speed: float):
    proc = await asyncio.create_subprocess_exec(
        "voicemode", "converse", "-m", message,
        "--voice", voice, "--speed", str(speed), "--no-wait"
    )
    await proc.wait()

async def _speak_macos_say(message: str, voice: str):
    proc = await asyncio.create_subprocess_exec("say", "-v", voice, message)
    await proc.wait()
```

**Priority order for auto-detection:**
1. `voicemode` (if installed)
2. `say` (macOS built-in)
3. Silent mode (log to stderr only)

#### 1.6 Configuration: `config.py`

Loads from `~/.config/kimi-voice/config.toml` with fallbacks:

```toml
# ~/.config/kimi-voice/config.toml

[voice]
backend = "voicemode"       # "voicemode" | "say" | "kokoro" | "openai"
voice = "af_sky"            # Voice identifier
speed = 1.0                 # Speech rate

[idle]
timeout = 60                # Seconds before idle announcement
enabled = true

[events]
announce_turn_end = true    # Speak on task completion
announce_approval = true    # Speak on permission requests
announce_idle = true        # Speak on idle timeout
announce_errors = false     # Speak on errors/interruptions

[bridge]
kimi_command = "kimi"       # Path to kimi binary
extra_args = []             # Additional args to pass to kimi --wire
```

**Per-project override:** Check for `.kimi-voice.toml` in the current working directory, merge with global config.

---

### Component 2: MCP Registration (`mcp/`)

**Purpose:** Register VoiceMode as an MCP server so Kimi can call it proactively (model-driven voice).

#### 2.1 MCP Config Snippet: `mcp-config.json`

```json
{
  "mcpServers": {
    "voicemode": {
      "command": "uvx",
      "args": ["--refresh", "voice-mode"]
    }
  }
}
```

The installer merges this into `~/.kimi/mcp.json`.

#### 2.2 Installer Logic

```bash
# Merge voicemode MCP into Kimi config
KIMI_MCP="$HOME/.kimi/mcp.json"
if [ -f "$KIMI_MCP" ]; then
    # Merge using jq
    jq -s '.[0] * .[1]' "$KIMI_MCP" mcp/mcp-config.json > tmp.json
    mv tmp.json "$KIMI_MCP"
else
    mkdir -p "$HOME/.kimi"
    cp mcp/mcp-config.json "$KIMI_MCP"
fi
```

---

### Component 3: Kimi Skill (`skills/`)

**Purpose:** Instruct Kimi to use the voicemode MCP tool at appropriate moments (model-driven announcements).

#### 3.1 Skill: `voice-announce/SKILL.md`

```markdown
---
name: voice-announce
description: Voice announcement behaviour for task completions and user interactions
---

## Voice Announcements

You have access to a `voicemode` MCP tool that can speak messages aloud.
Use it in these situations:

### When to announce

1. **Task completion**: After completing a significant task, call voicemode
   to announce a brief (~10 word) summary of what was done.

2. **Before asking questions**: When you are about to ask the user a question
   with multiple options, first announce the question via voicemode so the
   user hears the context.

3. **Errors requiring guidance**: When you encounter an error you cannot
   resolve, announce it via voicemode and ask for help.

### How to announce

Call the voicemode MCP tool with:
- `message`: Keep it brief, 10 words maximum for summaries
- `wait_for_response`: Set to `false` for announcements, `true` only when
  you need voice input back

### Examples

- "Done: refactored the authentication module"
- "Which database would you prefer, Postgres or SQLite?"
- "Build failed with 3 errors, need your guidance"

### When NOT to announce

- Do not announce every single tool call or file read
- Do not announce intermediate steps in a multi-step task
- Do not announce when the user is actively typing (they are engaged)
```

#### 3.2 Installation

```bash
# Install skill globally for all Kimi sessions
SKILL_DIR="$HOME/.config/agents/skills/voice-announce"
mkdir -p "$SKILL_DIR"
cp skills/voice-announce/SKILL.md "$SKILL_DIR/"
```

---

### Component 4: Installer (`install.sh`)

**Purpose:** One-command setup for the entire system.

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "Kimi Voice Hooks Installer"
echo "=========================="

# 1. Check prerequisites
check_prereqs() {
    # Python 3.10+
    # kimi CLI installed
    # voicemode installed (warn if not, offer to install)
}

# 2. Install bridge
install_bridge() {
    # Copy bridge/ to ~/.local/share/kimi-voice/
    # Create symlink in ~/.local/bin/kimi-voice
    # Make executable
}

# 3. Register MCP
register_mcp() {
    # Merge voicemode into ~/.kimi/mcp.json
}

# 4. Install skill
install_skill() {
    # Copy skill to ~/.config/agents/skills/voice-announce/
}

# 5. Create default config
create_config() {
    # Write ~/.config/kimi-voice/config.toml if not exists
}

# 6. Run validation
validate() {
    # Run tests/test-bridge.sh
}
```

---

### Component 5: Tests (`tests/`)

#### 5.1 Mock Wire Server: `mock-wire-server.py`

A Python script that mimics Kimi's Wire protocol output for testing:

```python
"""Emit a sequence of Wire protocol events to stdout for bridge testing."""
import json, sys, time

def emit(method, params):
    msg = {"jsonrpc": "2.0", "method": method, "params": params}
    print(json.dumps(msg), flush=True)

# Simulate a turn
emit("event", {"type": "TurnBegin", "payload": {}})
time.sleep(0.5)
emit("event", {"type": "ContentPart", "payload": {"content": "I have refactored the authentication module and added unit tests."}})
time.sleep(0.5)
emit("event", {"type": "TurnEnd", "payload": {}})
time.sleep(2)

# Simulate approval request
emit("request", {"type": "ApprovalRequest", "payload": {
    "id": "approval-1",
    "tool_call_id": "tc-1",
    "sender": "Shell",
    "action": "run shell command: npm test"
}})
```

#### 5.2 Unit Tests: `test_events.py`

Test each event handler in isolation:
- `test_turn_end_single_sentence` - Summary truncation
- `test_turn_end_empty` - Fallback message
- `test_approval_request_with_action` - Action extraction
- `test_approval_request_without_action` - Fallback to sender
- `test_approval_request_shell_prefix_stripped` - Prefix cleaning
- `test_idle_tracker_fires` - Timer fires after timeout
- `test_idle_tracker_resets` - Timer resets on activity
- `test_config_loading` - TOML config parsing
- `test_config_project_override` - Local config merges with global

#### 5.3 Integration Test: `test-bridge.sh`

End-to-end test using the mock server:

```bash
#!/bin/bash
# 1. Start mock wire server
# 2. Pipe through bridge (with voicemode mocked to echo)
# 3. Verify voice output messages
# 4. Verify approval request was forwarded
# 5. Verify idle timer fired
```

#### 5.4 Voice Test: `test-voice.sh`

Quick validation that voice output works:

```bash
#!/bin/bash
# Test each TTS backend
# voicemode, say, silent fallback
```

---

## Implementation Tasks

### Phase 1: Foundation (can be done in parallel)

These three workstreams have no dependencies on each other:

```
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│   Workstream A  │  │   Workstream B  │  │   Workstream C  │
│                 │  │                 │  │                 │
│  Voice Output   │  │  MCP + Skill    │  │  Config System  │
│  Abstraction    │  │  Registration   │  │                 │
│                 │  │                 │  │                 │
│  • voice.py     │  │  • mcp-config   │  │  • config.py    │
│  • TTS backends │  │  • SKILL.md     │  │  • config.toml  │
│  • test-voice   │  │  • install step │  │  • per-project  │
│                 │  │                 │  │    override     │
└────────┬────────┘  └────────┬────────┘  └────────┬────────┘
         │                    │                     │
         └────────────────────┼─────────────────────┘
                              │
                              ▼
```

#### A1: Voice Output Abstraction (`voice.py`)
- [ ] Implement `speak()` async function
- [ ] Implement `_speak_voicemode()` backend
- [ ] Implement `_speak_macos_say()` backend
- [ ] Implement auto-detection of available backend
- [ ] Implement silent fallback (stderr logging)
- [ ] Write `tests/test-voice.sh`

#### B1: MCP Registration
- [ ] Create `mcp/mcp-config.json`
- [ ] Write merge logic for `~/.kimi/mcp.json`
- [ ] Test that Kimi can discover and call voicemode after registration

#### B2: Kimi Skill
- [ ] Create `skills/voice-announce/SKILL.md`
- [ ] Test skill discovery (run `kimi` and check `/skill:voice-announce` is available)
- [ ] Iterate on prompt wording to ensure Kimi reliably calls voicemode

#### C1: Configuration System (`config.py`)
- [ ] Define `Config` dataclass/model
- [ ] Implement TOML loading from `~/.config/kimi-voice/config.toml`
- [ ] Implement per-project override from `.kimi-voice.toml`
- [ ] Implement `.voice` file support (compatibility with Claude voice hooks)
- [ ] Create default `config/kimi-voice.toml`
- [ ] Write `tests/test_events.py::test_config_*` tests

---

### Phase 2: Wire Bridge Core (sequential, depends on Phase 1)

```
┌─────────────────────────────────────────────┐
│              Wire Bridge Core               │
│                                             │
│  Depends on: voice.py, config.py            │
│                                             │
│  • bridge.py (subprocess + async I/O)       │
│  • events.py (event type handlers)          │
│  • idle_tracker.py                          │
│  • kimi-voice entry point                   │
│                                             │
└─────────────────────────────────────────────┘
```

#### D1: Bridge Process Management (`bridge.py`)
- [ ] Spawn `kimi --wire` subprocess
- [ ] Implement async stdin forwarding (terminal -> Kimi)
- [ ] Implement async stdout reading (Kimi -> terminal)
- [ ] Parse JSON-RPC messages from stdout stream
- [ ] Handle `initialize` handshake
- [ ] Handle graceful shutdown (SIGINT, SIGTERM, subprocess exit)
- [ ] Forward stderr from Kimi subprocess to terminal stderr

#### D2: Event Handlers (`events.py`)
- [ ] Implement `on_turn_begin()` - reset idle timer
- [ ] Implement `on_turn_end()` - announce task summary
- [ ] Implement `on_content_part()` - accumulate text
- [ ] Implement `on_approval_request()` - announce permission, forward to user
- [ ] Implement `on_step_interrupted()` - announce if unexpected
- [ ] Implement `on_tool_call()` - track for context
- [ ] Write unit tests for each handler

#### D3: Idle Tracker (`idle_tracker.py`)
- [ ] Implement `IdleTracker` class with configurable timeout
- [ ] Implement reset-on-activity logic
- [ ] Implement one-shot announcement (don't repeat until reset)
- [ ] Wire into bridge's event loop
- [ ] Write unit tests

#### D4: Entry Point (`kimi-voice`)
- [ ] Create shell wrapper script
- [ ] Add dependency checks
- [ ] Pass through all CLI arguments to `kimi --wire`
- [ ] Handle `--help` and `--version` flags

---

### Phase 3: Integration & Polish (depends on Phase 2)

```
┌──────────────────┐  ┌──────────────────┐
│   Workstream E   │  │   Workstream F   │
│                  │  │                  │
│  Testing &       │  │  Installer &     │
│  Validation      │  │  Documentation   │
│                  │  │                  │
│  • mock server   │  │  • install.sh    │
│  • integration   │  │  • README.md     │
│  • edge cases    │  │  • troubleshoot  │
│                  │  │                  │
└──────────────────┘  └──────────────────┘
        (parallel)
```

#### E1: Mock Wire Server
- [ ] Create `tests/mock-wire-server.py`
- [ ] Emit full turn cycle (TurnBegin, ContentPart, ToolCall, TurnEnd)
- [ ] Emit ApprovalRequest requiring response
- [ ] Emit rapid successive turns
- [ ] Emit empty turns

#### E2: Integration Tests
- [ ] End-to-end: bridge + mock server + mocked voice output
- [ ] Verify TurnEnd produces voice announcement
- [ ] Verify ApprovalRequest produces voice announcement and is forwarded
- [ ] Verify idle timer fires after configured timeout
- [ ] Verify idle timer resets on user input
- [ ] Verify config overrides work
- [ ] Verify graceful shutdown

#### F1: Installer
- [ ] Implement `install.sh` with all steps
- [ ] Add uninstall support (`install.sh --uninstall`)
- [ ] Add upgrade support (`install.sh --upgrade`)
- [ ] Validate prerequisites with clear error messages

#### F2: Documentation
- [ ] Write `README.md` (mirror style of Claude voice hooks README)
- [ ] Write troubleshooting guide
- [ ] Add usage examples
- [ ] Document configuration options
- [ ] Document differences from Claude voice hooks

---

## Task Dependency Graph

```
Phase 1 (parallel):
  A1 ─────────────────────────┐
  B1 + B2 ────────────────────┤
  C1 ─────────────────────────┤
                               │
Phase 2 (sequential):          ▼
  D1 → D2 → D3 → D4 ─────────┤
                               │
Phase 3 (parallel):            ▼
  E1 + E2 ────────────────────┤
  F1 + F2 ────────────────────┘
```

**Estimated task count:** 30 tasks across 3 phases

**Critical path:** A1 + C1 → D1 → D2 → D3 → D4 → E2

---

## Key Technical Decisions

### 1. Wire Mode vs Terminal Scraping

**Decision:** Wire Mode.

Wire gives typed, structured JSON events. Terminal scraping is fragile, depends on ANSI formatting, and breaks across versions. Wire is Kimi's officially supported integration protocol.

### 2. Python vs Node.js vs Bash for the Bridge

**Decision:** Python.

- Kimi CLI itself is Python, so users already have a suitable Python runtime
- `asyncio` handles bidirectional streaming well
- JSON-RPC parsing is trivial in Python
- The existing Claude hooks use Python one-liners for JSON; full Python is the natural next step
- Keeps dependencies minimal (no npm ecosystem needed)

### 3. Bridge (Proxy) vs Background Watcher

**Decision:** Proxy bridge (wraps `kimi --wire`).

A background watcher would need to parse terminal output or poll files. The proxy bridge sits in the communication path and sees every message natively. Tradeoff: user must run `kimi-voice` instead of `kimi`. Mitigated by shell alias in installer.

### 4. ApprovalRequest Handling

**Decision:** Forward to terminal, do not auto-respond.

The bridge announces the permission request via voice, then forwards the JSON-RPC request to the user's terminal for them to respond. The bridge never approves or rejects on behalf of the user. This matches Claude Code's behaviour where the hook is purely informational.

**Implementation note:** Wire mode's ApprovalRequest is a `request` (not `event`), meaning it requires a JSON-RPC response. The bridge must:
1. Display the approval prompt to the user (render in terminal)
2. Capture the user's response (approve/reject)
3. Send the JSON-RPC response back to Kimi

This is the most complex part of the bridge. Consider whether to:
- **(Option A)** Implement a minimal TUI prompt (recommended, simpler)
- **(Option B)** Forward raw JSON-RPC and let the user respond in JSON (developer-friendly but poor UX)
- **(Option C)** Use Kimi's `term` subcommand to handle rendering and only intercept events (investigate feasibility)

### 5. Voice Backend Priority

**Decision:** VoiceMode first, macOS `say` fallback, silent last.

VoiceMode provides the best quality and consistency with the Claude hooks ecosystem. macOS `say` is a zero-dependency fallback. Silent mode (stderr logging) ensures the bridge never crashes due to missing TTS.

---

## Edge Cases to Handle

| Scenario | Behaviour |
|----------|-----------|
| VoiceMode not installed | Fall back to `say`, warn on first use |
| Kimi exits unexpectedly | Bridge exits cleanly, no orphan processes |
| User sends Ctrl+C | Forward SIGINT to Kimi, clean up bridge |
| Rapid successive TurnEnd events | Debounce: only announce last one within 2-second window |
| Very long content in TurnEnd | Truncate to 10 words, append "..." |
| ApprovalRequest timeout | Do not auto-respond; user must act |
| Multiple Kimi sessions | Each bridge instance is independent |
| No internet (OpenAI TTS) | Fall back to Kokoro or `say` |
| `.kimi-voice.toml` missing | Use global config only |
| Wire protocol version mismatch | Log warning, attempt best-effort parsing |

---

## Compatibility Notes

### With Claude Voice Hooks

- The `.voice` file convention is shared: same file works for both systems
- VoiceMode MCP server is shared: same installation works for both
- Voice identifiers are the same (Kokoro/OpenAI voice names)
- Configuration files are separate (`settings.json` vs `config.toml`) to avoid conflicts

### Kimi CLI Versions

- Wire Mode was introduced early and is stable
- `ApprovalRequest` event available since Wire protocol 1.0
- `TurnEnd` event available since Wire protocol 1.2
- `replay` request available since Wire protocol 1.3 (not needed)
- **Minimum required version:** Kimi CLI with Wire protocol 1.2+

---

## Open Questions

1. **ApprovalRequest rendering:** Should the bridge implement its own terminal prompt for approvals, or attempt to use Kimi's existing terminal rendering? The former is more reliable but requires building a small TUI; the latter is less code but may not be feasible with Wire mode.

2. **Shell alias installation:** Should the installer add `alias kimi=kimi-voice` to the user's shell profile? This makes voice the default but changes user expectations. Alternative: keep them separate and let the user choose.

3. **Kimi `term` subcommand:** Kimi has a `kimi term` TUI mode. Investigate whether Wire mode can be combined with `term` to get the best of both worlds (full TUI + event interception).

4. **Subagent events:** Wire protocol emits `SubagentEvent` for sub-agent activity. Should the bridge announce sub-agent completions, or only top-level turns?

---

## Success Criteria

1. Running `kimi-voice "help me refactor auth"` produces voice announcements on:
   - Task completion (TurnEnd)
   - Permission requests (ApprovalRequest)
   - Idle timeout (60 seconds of no user input after TurnEnd)

2. Running `kimi` with the voicemode MCP registered allows Kimi to proactively speak via the `/skill:voice-announce` skill

3. Configuration via `~/.config/kimi-voice/config.toml` and per-project `.kimi-voice.toml` works

4. `.voice` file is shared between Claude and Kimi hooks

5. All tests pass: unit tests, integration tests, voice output tests

6. Installer works on a clean machine with only `kimi` and `python3` pre-installed
