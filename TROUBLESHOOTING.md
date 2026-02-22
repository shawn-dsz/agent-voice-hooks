# Troubleshooting Guide: Kimi Voice Hooks

Common issues and solutions for Kimi Voice Hooks.

## Table of Contents

- [Bridge Not Starting](#bridge-not-starting)
- [No Voice Output](#no-voice-output)
- [MCP Not Working](#mcp-not-working)
- [Skill Not Available](#skill-not-available)
- [Idle Timer Not Firing](#idle-timer-not-firing)
- [Approval Requests Not Announced](#approval-requests-not-being-announced)
- [Wire Protocol Issues](#wire-protocol-issues)
- [Platform-Specific Issues](#platform-specific-issues)

---

## Bridge Not Starting

### Problem: `kimi-voice` command not found

**Check PATH:**
```bash
which kimi-voice
```

If not found, ensure `~/.local/bin` is in your PATH:
```bash
export PATH="$HOME/.local/bin:$PATH"
```

Add to your shell profile (`~/.bashrc`, `~/.zshrc`, etc.) to make permanent.

### Problem: Python version error

**Check Python version:**
```bash
python3 --version  # Must be 3.10+
```

If you have multiple Python versions:
```bash
# Find Python 3.10+
which python3.10 || which python3.11 || which python3.12

# Install with specific Python
PYTHON_CMD=python3.11 ./install.sh
```

### Problem: `kimi` not found

**Verify Kimi CLI is installed:**
```bash
which kimi
kimi --version
```

If Kimi is installed but not in PATH:
```bash
# Edit config to specify full path
~/.config/kimi-voice/config.toml

[bridge]
kimi_command = "/path/to/kimi"
```

Or use environment variable:
```bash
export KIMI_VOICE_KIMI_COMMAND="/path/to/kimi"
```

---

## No Voice Output

### Problem: No audio is heard

**Step 1: Check backend detection**

```bash
python3 ~/.local/share/kimi-voice/voice.py --info
```

Expected output:
```json
{
  "voicemode": { "available": true, "detected": true },
  "say": { "available": true, "detected": false },
  "silent": { "available": true, "detected": false },
  "selected": "voicemode"
}
```

**Step 2: Test each backend directly**

```bash
# Test voicemode (if installed)
voicemode converse -m "Test message" --no-wait

# Test macOS say
say -v Samantha "Test message"

# Test silent (should log to stderr)
python3 ~/.local/share/kimi-voice/voice.py --backend silent "Test message"
```

**Step 3: Check system audio**

- System volume is up
- Correct output device selected
- No "Do Not Disturb" or focus mode blocking

### Problem: VoiceMode not working

**Install VoiceMode:**
```bash
# Install uv if needed
curl -LsSf https://astral.sh/uv/install.sh | sh

# Install VoiceMode
uvx voice-mode-install

# Verify
voicemode --version
voicemode converse -m "Hello" --no-wait
```

### Problem: Specific voice not working

**Check voice availability:**
```bash
# VoiceMode voices
voicemode voices list

# macOS voices
say -v '?'
```

**Try default voice:**
```toml
# ~/.config/kimi-voice/config.toml
[voice]
backend = "voicemode"
voice = "af_sky"  # Default, high-quality voice
```

---

## MCP Not Working

### Problem: voicemode MCP not registered

**Check MCP config:**
```bash
cat ~/.kimi/mcp.json
```

Should contain:
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

**Re-register MCP:**
```bash
# Method 1: Using install script
./install.sh

# Method 2: Manual registration
kimi mcp add voicemode -- uvx --refresh voice-mode

# Method 3: Using mcp install script
./mcp/install-mcp.sh
```

### Problem: MCP config is invalid

**Validate JSON:**
```bash
python3 -c "import json; json.load(open('$HOME/.kimi/mcp.json'))"
```

If invalid, fix or backup and recreate:
```bash
cp ~/.kimi/mcp.json ~/.kimi/mcp.json.backup
./mcp/install-mcp.sh
```

### Problem: Kimi can't find voicemode tool

**List available MCP tools:**
```
In Kimi: /mcp:list
```

**Check for errors:**
```bash
# Run Kimi with verbose MCP logging
kimi --mcp-debug
```

---

## Skill Not Available

### Problem: `/skill:voice-announce` not found

**Verify skill installation:**
```bash
ls -la ~/.config/agents/skills/voice-announce/
```

Should contain `SKILL.md`.

**Re-install skill:**
```bash
./install.sh
```

Or manually:
```bash
mkdir -p ~/.config/agents/skills/voice-announce
cp skills/voice-announce/SKILL.md ~/.config/agents/skills/voice-announce/
```

**Check skill format:**

The SKILL.md must start with valid frontmatter:
```yaml
---
name: voice-announce
description: Voice announcement behaviour...
tools:
  - voicemode
tags:
  - voice
  - notifications
---
```

---

## Idle Timer Not Firing

### Problem: Never hear idle announcement

**Check idle is enabled:**
```bash
grep -A2 '\[idle\]' ~/.config/kimi-voice/config.toml
```

Should show:
```toml
[idle]
timeout = 60
enabled = true
```

**Verify timeout value:**
- Default is 60 seconds
- Timer only fires after 60 seconds of inactivity
- Must be preceded by a TurnEnd event (Kimi finishing a response)

**Check bridge is running:**
```bash
# In another terminal, while kimi-voice is running
ps aux | grep kimi-voice
```

**Test with shorter timeout:**
```bash
# Temporarily use 10-second timeout
KIMI_VOICE_IDLE_TIMEOUT=10 kimi-voice "hello"
```

### Problem: Idle announcement fires too frequently

The idle tracker uses a one-shot mechanism - it should only announce once until reset. If you hear it repeatedly:

**Check for multiple bridge instances:**
```bash
ps aux | grep -c "kimi-voice\|bridge.py"
```

Kill duplicates:
```bash
pkill -f "bridge.py"
```

---

## Approval Requests Not Being Announced

### Problem: Permission prompts don't trigger voice

**Enable approval announcements:**
```toml
# ~/.config/kimi-voice/config.toml
[events]
announce_approval = true
```

**Check Wire protocol support:**

The bridge intercepts `ApprovalRequest` events from Kimi's Wire protocol. Verify Kimi supports this:

```bash
# Check Kimi version
kimi --version
```

**Test with debug mode:**
```bash
KIMI_VOICE_DEBUG=1 kimi-voice "run a command that needs permission"
```

Look for lines like:
```
[bridge] ApprovalRequest received: {...}
[voice] Speaking: "Waiting for permission to..."
```

### Problem: Approval request forwarded but not announced

If the approval prompt appears but you don't hear anything:

1. Check TTS backend is working (see [No Voice Output](#no-voice-output))
2. Verify `announce_approval` is enabled in config
3. Check if voice is muted in system settings

---

## Wire Protocol Issues

### Problem: JSON parse errors in bridge

**Enable debug mode:**
```bash
KIMI_VOICE_DEBUG=1 kimi-voice "test" 2>&1 | tee bridge.log
```

**Common causes:**
- Non-JSON output from Kimi (progress bars, etc.)
- Binary data in output
- Partial JSON messages

The bridge should handle these gracefully, but debug output will show warnings.

### Problem: Protocol version mismatch

If you see warnings about protocol version:

```
[bridge] Warning: Wire protocol version X.Y may not be fully supported
```

The bridge attempts best-effort parsing. Most events should work regardless of version.

**Update the bridge:**
```bash
./install.sh --upgrade
```

### Problem: Events not being intercepted

**Verify Wire mode is active:**

The bridge automatically adds `--wire` to Kimi arguments. Verify:
```bash
# Should show process with --wire
ps aux | grep "kimi.*--wire"
```

---

## Debugging with KIMI_VOICE_DEBUG

Enable detailed debug output:

```bash
KIMI_VOICE_DEBUG=1 kimi-voice "your prompt"
```

Debug output includes:
- All Wire protocol messages
- Event detection
- Voice announcement triggers
- Configuration loading

**Save debug log:**
```bash
KIMI_VOICE_DEBUG=1 kimi-voice "test" 2>&1 | tee kimi-voice-debug.log
```

---

## Platform-Specific Issues

### macOS

**Issue: `say` command not found**
- `say` is built into macOS and should always be available
- If missing, your macOS installation may be incomplete

**Issue: Audio output to wrong device**
```bash
# Check current output device
SwitchAudioSource -c

# List devices
SwitchAudioSource -a

# Set device
SwitchAudioSource -s "Device Name"
```

Install SwitchAudioSource: `brew install switchaudio-osx`

**Issue: Permission denied for microphone (VoiceMode)**
- VoiceMode needs microphone access for conversational mode
- Go to System Settings > Privacy & Security > Microphone
- Ensure Terminal (or iTerm) has microphone access

### Linux

**Issue: No TTS backend available**

Linux doesn't have a built-in TTS like macOS `say`. Options:

1. **Install VoiceMode** (recommended):
   ```bash
   uvx voice-mode-install
   ```

2. **Install espeak** (fallback):
   ```bash
   sudo apt-get install espeak  # Debian/Ubuntu
   sudo yum install espeak      # RHEL/CentOS
   ```
   Note: The bridge doesn't currently support espeak directly, but you could create a wrapper script.

3. **Use silent mode** (no audio):
   ```toml
   [voice]
   backend = "silent"
   ```

**Issue: Audio system not detected**

The bridge relies on the TTS backends to handle audio output. If using VoiceMode, ensure:
```bash
# PulseAudio or PipeWire is running
pulseaudio --check || pipewire --version

# Audio device is available
aplay -l  # For ALSA
pactl list sinks  # For PulseAudio
```

### Windows (WSL)

**Issue: No audio in WSL**

WSL requires additional setup for audio:

1. Install PulseAudio for Windows
2. Configure WSL to use Windows audio
3. Or use silent mode

The bridge hasn't been tested on native Windows.

---

## Getting Help

If none of these solutions work:

1. **Run diagnostics:**
   ```bash
   ./tests/test-voice.sh --diagnostics
   ```

2. **Collect debug info:**
   ```bash
   KIMI_VOICE_DEBUG=1 kimi-voice "test" 2>&1 | tee debug.log
   # Include debug.log in your issue
   ```

3. **Check versions:**
   ```bash
   python3 --version
   kimi --version
   voicemode --version 2>/dev/null || echo "voicemode not installed"
   uname -a
   ```

4. **File an issue:**
   - https://github.com/yourusername/kimi-voice-hooks/issues
   - Include: OS, Python version, Kimi version, debug log

---

## Useful Commands

```bash
# Test voice directly
voicemode converse -m "Test message" --no-wait
say -v Samantha "Test message"  # macOS

# Validate config
cat ~/.config/kimi-voice/config.toml

# Check MCP config
cat ~/.kimi/mcp.json | python3 -m json.tool

# List installed files
ls -la ~/.local/share/kimi-voice/
ls -la ~/.local/bin/kimi-voice

# Check bridge is in PATH
which kimi-voice
echo $PATH | tr ':' '\n' | grep local

# Reinstall without overwriting config
./install.sh --upgrade
```
