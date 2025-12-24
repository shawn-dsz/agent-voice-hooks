# Repository-Specific Voice Configuration

> **Customize voice notifications per project** — use different voices, speeds, or behaviors for each repository.

---

## Why Per-Repository Configuration?

Different projects may benefit from different voice settings:

| Use Case | Example Configuration |
|----------|----------------------|
| **Work vs. personal projects** | Professional voice for work, casual for personal |
| **Different team members** | Male voice for projects shared with one colleague, female for another |
| **Project importance** | Normal speed for routine tasks, slower for critical deployments |
| **Language preferences** | English voice for most projects, accent-specific for international teams |

---

## How It Works

Your global hooks use the `$CLAUDE_PROJECT_DIR` variable, which points to each project's root directory:

```json
// In ~/.claude/settings.json
{
  "hooks": {
    "Stop": [{
      "hooks": [{
        "type": "command",
        "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/task-summary.sh"
      }]
    }]
  }
}
```

This means **project-local hooks take precedence** over global hooks. If a repository has its own `.claude/hooks/` folder, those scripts are used instead of the global ones.

---

## Setup

### Step 1: Create Project-Local Hooks Directory

In your project repository, create the hooks folder:

```bash
cd /path/to/your-project
mkdir -p .claude/hooks
```

### Step 2: Copy Hook Scripts (Optional)

If you want to start from the existing global hooks:

```bash
cp ~/.claude/hooks/task-summary.sh .claude/hooks/
cp ~/.claude/hooks/notification-idle.sh .claude/hooks/
cp ~/.claude/hooks/permission-request.sh .claude/hooks/
```

### Step 3: Customize Voice Settings

Edit each hook script to add your preferred voice:

```bash
# .claude/hooks/task-summary.sh
voicemode converse -m "Task completed" --voice am_adam --no-wait
```

---

## Examples

### Example 1: Male Voice for a Specific Repository

**File:** `/projects/work-repo/.claude/hooks/task-summary.sh`

```bash
#!/usr/bin/env bash

voicemode converse -m "Work task completed" --voice am_adam --no-wait
```

### Example 2: Faster Speech for Quick Iteration Projects

**File:** `/projects/prototype-repo/.claude/hooks/task-summary.sh`

```bash
#!/usr/bin/env bash

voicemode converse -m "Done" --voice af_sky --speed 1.5 --no-wait
```

### Example 3: Different Voice for Permission Requests

**File:** `/projects/production-repo/.claude/hooks/permission-request.sh`

```bash
#!/usr/bin/env bash

# Use a more serious voice for production deployments
voicemode converse -m "$MESSAGE" --voice bm_george --no-wait
```

### Example 5: Work vs Personal Projects

Use different voice personalities to quickly identify context by sound alone:

**Work project** (`/projects/work-api/.claude/hooks/task-summary.sh`):
```bash
#!/usr/bin/env bash
voicemode converse -m "Work task completed" --voice am_adam --speed 1.0 --no-wait
```

**Personal project** (`/projects/personal-blog/.claude/hooks/task-summary.sh`):
```bash
#!/usr/bin/env bash
voicemode converse -m "Done!" --voice af_sky --speed 1.3 --no-wait
```

### Example 6: Production vs Development

Use a more serious, slower voice for production-related work:

**Development** (`/projects/app-repo/.claude/hooks/task-summary.sh`):
```bash
#!/usr/bin/env bash
voicemode converse -m "Dev task done" --voice af_sky --speed 1.2 --no-wait
```

**Production** (create `/projects/app-repo/.claude/hooks/production-deploy.sh` for deployment tasks):
```bash
#!/usr/bin/env bash
# Use deeper, slower voice for production announcements
voicemode converse -m "Production deployment completed" --voice onyx --speed 0.9 --tts-provider openai --no-wait
```

### Example 4: Environment Variable Override

Set voice preferences at the script level:

```bash
#!/usr/bin/env bash

# Override default voice for this project only
export VOICEMODE_KOKORO_DEFAULT_VOICE="am_michael"

voicemode converse -m "Custom voice announcement" --no-wait
```

### Example 5: Silent Mode for Meetings

When you're in meetings, you may want voice notifications disabled or very quiet:

**Option A: Disable voice entirely**
```bash
#!/usr/bin/env bash
# Silent mode - exit without speaking
exit 0
```

**Option B: Minimal whisper messages**
```bash
#!/usr/bin/env bash
voicemode converse -m "." --speed 0.5 --no-wait
```

**Option C: Environment variable toggle**
```bash
#!/usr/bin/env bash
# Check for SILENT_MODE environment variable
if [ "$SILENT_MODE" = "1" ]; then
    exit 0
fi

voicemode converse -m "$MESSAGE" --no-wait
```

To enable silent mode:
```bash
export SILENT_MODE=1
```

---

## Available Voice Options

### Kokoro (Local TTS)

| Voice | Gender | Description |
|-------|--------|-------------|
| `af_sky` | Female | Natural, clear |
| `af_sarah` | Female | Warm tone |
| `am_adam` | Male | Balanced, professional |
| `am_michael` | Male | Deeper voice |
| `ef_dora` | Female | Energetic |
| `bm_george` | Male | Authoritative |
| `bm_lewis` | Male | Calm, steady |

### OpenAI (Cloud TTS)

| Voice | Gender | Description |
|-------|--------|-------------|
| `nova` | Female | Friendly, expressive |
| `shimmer` | Female | Clear, articulate |
| `alloy` | Neutral | Balanced, versatile |
| `echo` | Male | Deep, resonant |
| `fable` | Male | Warm, storytelling |
| `onyx` | Male | Professional, firm |

---

## Additional Parameters

Beyond voice selection, you can customize:

| Parameter | Values | Description |
|-----------|--------|-------------|
| `--speed` | 0.25 - 4.0 | Playback speed (1.0 = normal) |
| `--tts-provider` | `kokoro` \| `openai` | Force specific TTS provider |
| `--tts-model` | `tts-1` \| `tts-1-hd` | Audio quality (OpenAI only) |

---

## Troubleshooting

### Project Hooks Not Being Used

**Problem:** Global hooks are still being used instead of project-local ones.

**Solution:** Verify your `~/.claude/settings.json` uses `$CLAUDE_PROJECT_DIR`:

```json
"command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/task-summary.sh"
```

### Hook Scripts Not Executable

**Problem:** Permission denied when running hooks.

**Solution:** Make scripts executable:

```bash
chmod +x .claude/hooks/*.sh
```

### Voice Not Available

**Problem:** Error about voice not being found.

**Solution:** Check available voices for your provider:

- **Kokoro:** Ensure the voice is in the Kokoro voice list
- **OpenAI:** Verify your API key has access to the voice

---

## See Also

- [README.md](./README.md) - Main project documentation
- [VoiceMode Parameters](https://voice-mode.readthedocs.io/en/latest/) - Complete parameter reference
- [Claude Code Settings](https://code.claude.com/docs/en/settings) - Configuration hierarchy
