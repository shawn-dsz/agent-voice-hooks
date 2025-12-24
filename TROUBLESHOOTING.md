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
   chmod +x .claude/hooks/*.sh
   ```

4. **Wrong command path in settings.json**
   - Verify path uses `$CLAUDE_PROJECT_DIR` environment variable
   - Verify path is correct for your project structure

## No Voice Output

### Problem: Hooks run but no voice is heard

**Check Kokoro Service:**

```bash
voicemode service status kokoro
```

If not running:
```bash
voicemode service start kokoro
```

**Verify voicemode works directly:**

```bash
voicemode converse -m "Test message" --no-wait
```

**Check audio output:**
- System volume is up
- Correct output device selected in System Settings
- No other app blocking audio

## Kokoro Service Won't Start

### Problem: Kokoro TTS service fails to start

**Check port availability:**
```bash
lsof -i :8880  # Kokoro default port
```

If port is in use, either:
- Kill the process using port 8880
- Or configure Kokoro to use a different port

**Check service logs:**
```bash
voicemode service logs kokoro
```

**Reinstall Kokoro:**
```bash
brew reinstall voicemode
```

## settings.json Conflicts

### Problem: Existing settings.json needs hooks merged

If your project already has a `settings.json`, you need to merge the hooks configuration.

**Current settings.json example:**
```json
{
  "permissions": {
    "allow": ["*"]
  }
}
```

**After merging hooks:**
```json
{
  "permissions": {
    "allow": ["*"]
  },
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/task-summary.sh"
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
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/notification-idle.sh"
          }
        ]
      },
      {
        "matcher": "permission_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/permission-request.sh"
          }
        ]
      }
    ]
  }
}
```

**Quick merge with jq:**
```bash
jq '. + {
  "hooks": {
    "Stop": [{ "hooks": [{ "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/task-summary.sh" }] }],
    "Notification": [
      { "matcher": "idle_prompt", "hooks": [{ "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/notification-idle.sh" }] },
      { "matcher": "permission_prompt", "hooks": [{ "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/permission-request.sh" }] }
    ]
  }
}' .claude/settings.json > .claude/settings.json.new
mv .claude/settings.json.new .claude/settings.json
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
  "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/task-summary.sh",
  "timeout": 120
}
```

## Voice Quality Issues

### Problem: Voice sounds distorted or cuts off

**Check Kokoro service health:**
```bash
voicemode service status kokoro
voicemode service logs kokoro | tail -20
```

**Restart Kokoro service:**
```bash
voicemode service restart kokoro
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
jq '.hooks.Notification[] | select(.matcher == "idle_prompt")' .claude/settings.json
```

Should return:
```json
{
  "matcher": "idle_prompt",
  "hooks": [...]
}
```

## Permission Hook Shows Wrong Tool Name

### Problem: Hears "Claude needs permission to use unknown"

This means the JSON parsing in `permission-request.sh` failed.

**Debug:**
```bash
echo '{"tool":"Write","file_path":"test.txt"}' | ./.claude/hooks/permission-request.sh
```

**Common fix:** Ensure Python 3 is installed:
```bash
python3 --version
```

## Getting Help

If none of these solutions work:

1. **Run the test script:**
   ```bash
   ./.claude/hooks/test-hooks.sh
   ```

2. **Check Claude Code logs:**
   ```bash
   claude --debug
   ```

3. **Check hook execution:**
   ```bash
   # Run hooks directly with verbose output
   bash -x ./.claude/hooks/task-summary.sh
   ```

4. **File an issue:**
   - For voicemode issues: https://github.com/voicemode/voicemode/issues
   - For Claude Code issues: https://github.com/anthropics/claude-code/issues

## Useful Commands

```bash
# Check all voicemode services
voicemode service status kokoro
voicemode service status whisper

# View service logs
voicemode service logs kokoro --lines 50

# Restart services
voicemode service restart kokoro

# Test TTS directly
voicemode converse -m "Test message" --no-wait

# Validate settings.json
jq . .claude/settings.json

# Check hook script permissions
ls -la .claude/hooks/

# Test hook manually
echo '{"tool":"Write"}' | ./.claude/hooks/permission-request.sh
```
