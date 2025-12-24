# Troubleshooting Guide

Common issues and solutions for Claude Code voice notification hooks.

## Hooks Not Triggering

### Problem: Hooks are registered but never run

**Possible Causes:**

1. **Claude Code hasn't been restarted** - Hooks are captured at startup
   - **Solution**: Fully restart Claude Code (quit and reopen)

2. **settings.json was modified externally** - Direct edits don't take effect immediately
   - **Solution**: Restart Claude Code or use `/hooks` command to review changes

3. **Hook scripts aren't executable**
   ```bash
   chmod +x ~/.claude/hooks/*.sh
   ```

4. **Wrong command path in settings.json**
   - Verify path uses `~/.claude/hooks/` for global installation
   - Verify path is correct for your setup

## No Voice Output

### Problem: Hooks run but no voice is heard

**Check VoiceMode MCP:**

```bash
claude mcp list
```

Verify voicemode is registered. If not:
```bash
claude mcp add --scope user voicemode -- uvx --refresh voice-mode
```

**Verify voicemode works directly:**

```bash
voicemode converse -m "Test message" --no-wait
```

**Check audio output:**
- System volume is up
- Correct output device selected in System Settings
- No other app blocking audio

## VoiceMode Not Installed

### Problem: voicemode command not found

**Install VoiceMode:**

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
uvx voice-mode-install
claude mcp add --scope user voicemode -- uvx --refresh voice-mode
```

## settings.json Conflicts

### Problem: Existing global settings.json needs hooks merged

If you already have a `~/.claude/settings.json`, you need to merge the hooks configuration.

**Quick merge with cat:**
```bash
cat .claude/settings.json >> ~/.claude/settings.json
```

**Or merge manually** — add the `hooks` section to your existing config:

```json
{
  "yourExisting": "settings",
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/task-summary.sh"
          }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "idle_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/notification-idle.sh"
          }
        ]
      },
      {
        "matcher": "permission_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/permission-request.sh"
          }
        ]
      }
    ]
  }
}
```

## Hooks Only Work Sometimes

### Problem: Intermittent hook execution

**Check for timeout issues:**
- Hooks have a 60-second timeout by default
- If voicemode is slow to respond, the hook may time out

**Solution**: Add a timeout to the hook command in settings.json:
```json
{
  "type": "command",
  "command": "~/.claude/hooks/task-summary.sh",
  "timeout": 120
}
```

## Voice Quality Issues

### Problem: Voice sounds distorted or cuts off

**Test voicemode directly:**
```bash
voicemode converse -m "Test" --no-wait
```

**Adjust voice settings** (if needed):
```bash
# Test different voices
voicemode converse -m "Test" --voice af_nova --no-wait
voicemode converse -m "Test" --voice af_sky --no-wait
voicemode converse -m "Test" --voice am_michael --no-wait
```

## Idle Notification Not Working

### Problem: Never hear "Claude is waiting for your input"

**Idle notifications only trigger after 60+ seconds** of no user input. This is by design.

To verify it's configured:
```bash
jq '.hooks.Notification[] | select(.matcher == "idle_prompt")' ~/.claude/settings.json
```

Should return:
```json
{
  "matcher": "idle_prompt",
  "hooks": [...]
}
```

## Permission Hook Shows Wrong Tool Name

### Problem: Hears "Claude is waiting to use unknown"

This means the JSON parsing in `permission-request.sh` failed.

**Debug:**
```bash
echo '{"tool":"Write","description":"Write to file"}' | ~/.claude/hooks/permission-request.sh
```

**Common fix:** Ensure Python 3 is installed:
```bash
python3 --version
```

## Getting Help

If none of these solutions work:

1. **Run the test script:**
   ```bash
   ~/.claude/hooks/test-hooks.sh
   ```

2. **Check Claude Code logs:**
   ```bash
   claude --debug
   ```

3. **Check hook execution:**
   ```bash
   # Run hooks directly with verbose output
   bash -x ~/.claude/hooks/task-summary.sh
   ```

4. **File an issue:**
   - For this repo: https://github.com/shawn-dsz/agent-voice-hooks/issues
   - For VoiceMode issues: https://github.com/voice-mode/voice-mode/issues
   - For Claude Code issues: https://github.com/anthropics/claude-code/issues

## Useful Commands

```bash
# Test TTS directly
voicemode converse -m "Test message" --no-wait

# Validate settings.json
jq . ~/.claude/settings.json

# Check hook script permissions
ls -la ~/.claude/hooks/

# Test permission hook manually
echo '{"tool":"Write","description":"Write to file"}' | ~/.claude/hooks/permission-request.sh
```
