# Voice Hooks Demo Guide

This guide provides commands you can run in Claude Code to demonstrate the voice hooks functionality.

## Prerequisites

1. **Install VoiceMode** (one-time):
   ```bash
   uvx voice-mode-install
   claude mcp add --scope user voicemode -- uvx --refresh voice-mode
   ```

2. **Install hooks in this project**:
   ```bash
   # Copy hooks to current project
   cp -r .claude/hooks ~/.claude/
   cat .claude/settings.json >> ~/.claude/settings.json
   ```

3. **Start voicemode services**:
   ```bash
   voicemode service start kokoro
   voicemode service status
   ```

---

## Demo Commands for Screen Recording

### Demo 1: Task Completion (Single Task)

Run this in Claude Code:
```
python3 -c "print('Hello, Voice Mode!')"
```

**Expected voice**: "Done: Print hello message" (or similar)

---

### Demo 2: Task Completion (Multiple Tasks)

Run this in Claude Code:
```
echo "Creating test file..." > test.txt && echo "Another task" >> test.txt && cat test.txt
```

**Expected voice**: "Done: 2 tasks. Last: Display contents of..."

---

### Demo 3: Permission Request (Write Tool)

Run this in Claude Code (requires permission approval):
```
echo "test" > /etc/hosts
```

**Expected voice**: "I am waiting for permission to Write test to /etc/hosts"

Then **deny** the permission in the UI.

---

### Demo 4: Permission Request (Bash Tool)

Run this in Claude Code (requires permission approval):
```
rm -rf /important/system/file
```

**Expected voice**: "I am waiting for permission to Remove important system file"

Then **deny** the permission.

---

### Demo 5: Idle Notification

Run this in Claude Code:
```
echo "Waiting for idle notification (will take 65 seconds)..." && sleep 65
```

**Expected voice after ~60 seconds**: "I am waiting for your next instruction for [project] on branch [branch]"

> **Tip for screen recording**: Speed up the video during the 60-second wait, then slow down when voice plays.

---

### Demo 6: AskUserQuestion Hook

Run this in Claude Code:
```
// Ask: What color should I use for the demo?
```

**Expected voice**: "I am waiting for your input with [project]"

---

## Demo Script (Automated Setup)

Run the provided demo script to set up a test project:

```bash
./demo.sh
```

This will create a demo project with sample files you can use for testing.

---

## Voice Customization Demo

Show how to change voices by editing a hook:

```bash
# Edit the task summary hook
nano ~/.claude/hooks/task-summary.sh
```

Change the voice parameter:
```bash
# From:
voicemode converse -m "$MESSAGE" --no-wait

# To (male voice):
voicemode converse -m "$MESSAGE" --voice am_adam --no-wait
```

---

## Repository-Specific Config Demo

Show different voices for different projects:

```bash
# In a "work" project - use professional voice
mkdir -p ~/work-project/.claude/hooks
echo 'voicemode converse -m "Work task done" --voice am_adam --no-wait' > ~/work-project/.claude/hooks/task-summary.sh

# In a "personal" project - use friendly voice
mkdir -p ~/personal-project/.claude/hooks
echo 'voicemode converse -m "Done!" --voice af_sky --no-wait' > ~/personal-project/.claude/hooks/task-summary.sh
```

---

## Screen Recording Tips

1. **Audio setup**: Make sure your system audio is being captured
2. **Volume**: Turn up speakers so the voice is clear
3. **Pacing**: Pause after each command to let the voice announcement play
4. **Idle demo**: Speed up the video during the 60-second wait
5. **Explain**: Call out what you're expecting to hear before each demo

---

## Troubleshooting

If voice doesn't play:

```bash
# Check voicemode services
voicemode service status

# Restart services
voicemode service restart kokoro

# Test voicemode directly
voicemode converse -m "Test message"
```
