# Feature Request: PreQuestion Hook for VoiceMode Integration

## Summary

Request for a new `PreQuestion` hook type in Claude Code that fires **before** `AskUserQuestion` is displayed to the user, with full question context passed to the hook via stdin.

## Problem

Currently, when Claude calls `AskUserQuestion`, the `permission_prompt` hook fires with limited data:

```json
{
  "tool": "AskUserQuestion",
  "description": ""  // Usually empty or generic
}
```

This means hooks cannot announce the actual question content via voicemode. Users hear "Claude needs permission to use a tool" instead of the actual question like "What real-time technology would you prefer for the live updates?"

## Proposed Solution

Add a new `PreQuestion` hook type that fires before the AskUserQuestion UI is shown, with full question context.

### Hook Configuration

```json
{
  "hooks": {
    "PreQuestion": [
      {
        "hooks": [
          {
            "type": "command",
            "command": ".claude/hooks/pre-question.sh",
            "timeout": 120
          }
        ]
      }
    ]
  }
}
```

### Event Data Schema

Pass the following JSON structure to the hook via stdin:

```json
{
  "tool": "AskUserQuestion",
  "question": "What real-time technology would you prefer for the live updates?",
  "header": "Real-time tech",
  "multiSelect": false,
  "options": [
    {
      "label": "Server-Sent Events (SSE)",
      "description": "One-way server-to-client streaming. Simpler, already used in chat. Good for dashboards where client just receives updates."
    },
    {
      "label": "WebSocket",
      "description": "Full duplex communication. More complex but allows bidirectional messaging if needed."
    },
    {
      "label": "Polling",
      "description": "Simple interval-based fetching (e.g., every 5 seconds). Easiest to implement but less efficient."
    }
  ]
}
```

### Execution Flow

1. Claude calls `AskUserQuestion` tool
2. **Before showing UI**: Claude Code fires `PreQuestion` hook
3. Hook receives question data via stdin
4. Hook executes (e.g., announces via voicemode)
5. Hook completes (respects timeout)
6. **Then**: Claude Code shows AskUserQuestion UI to user
7. User responds via UI
8. Response returned to Claude

### Timing Diagram

```
Time →

Claude makes tool call (AskUserQuestion)
    ↓
PreQuestion hook fires
    ↓ (stdin: full question JSON)
Hook script executes
    ↓ (e.g., voicemode announces question)
Hook completes (or timeout)
    ↓
AskUserQuestion UI shown to user
    ↓
User selects option
    ↓
Response returned to Claude
```

## Use Cases

### Primary: VoiceMode Announcement

Announce questions naturally via voice before showing the UI:

```bash
#!/bin/bash
# .claude/hooks/pre-question.sh

INPUT=$(cat)

# Extract question and options
QUESTION=$(echo "$INPUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['question'])")
OPTIONS=$(echo "$INPUT" | python3 -c "
import json, sys
data = json.load(sys.stdin)
opts = data.get('options', [])
parts = [f\"Option {i+1}: {opt['label']}\" for i, opt in enumerate(opts)]
print(', '.join(parts))
")

# Announce via voicemode
MESSAGE="$QUESTION. $OPTIONS"
voicemode converse -m "$MESSAGE" --no-wait
```

**User hears:** "What real-time technology would you prefer for the live updates? Option 1: Server-Sent Events, Option 2: WebSocket, Option 3: Polling"

### Secondary: Logging and Analytics

```bash
#!/bin/bash
# Log questions asked for analytics
INPUT=$(cat)
echo "$INPUT" | python3 -c "
import json, sys, datetime
data = json.load(sys.stdin)
log_entry = {
    'timestamp': datetime.datetime.now().isoformat(),
    'question': data['question'],
    'option_count': len(data.get('options', []))
}
with open('$HOME/.claude/question-log.jsonl', 'a') as f:
    f.write(json.dumps(log_entry) + '\n')
"
```

### Tertiary: Custom UI Integrations

Hooks could send question data to external systems (IDEs, notification systems, etc.) before the CLI shows the question.

## Benefits

1. **Better accessibility** - Screen reader users or voice-first users get full question context
2. **Consistent experience** - Questions announced the same way permissions are announced
3. **Extensibility** - Enables custom integrations and workflows
4. **No behavior change** - Existing code without hooks works identically

## Implementation Considerations

### Backwards Compatibility

- Existing configurations without `PreQuestion` hooks continue working
- No breaking changes to existing hook types
- Optional feature - users opt-in via configuration

### Performance

- Hook execution is async (doesn't block Claude)
- Timeout prevents hanging (default 60s, configurable)
- User sees no delay if hook completes quickly

### Security

- Same security model as existing hooks
- Hooks run in user's environment with user permissions
- No network access required (unless hook explicitly makes calls)

### Edge Cases

1. **Hook timeout**: If hook times out, proceed to show UI anyway
2. **Hook failure**: Log error but don't block question display
3. **Multiple hooks**: Execute in order, like existing hook types
4. **Empty options**: Pass empty array for "Other" input questions

## Comparison with Current Workaround

### Current Workaround (Claude behavior)

Claude manually calls voicemode before AskUserQuestion:

```python
converse("What real-time technology would you prefer?...", wait_for_response=False)
AskUserQuestion(...)
```

**Issues:**
- ❌ Relies on Claude following instructions consistently
- ❌ Question announced twice (voice + UI)
- ❌ No way to customize announcement format per-project
- ❌ Can't integrate with other systems

### With PreQuestion Hook

Hooks handle announcement automatically:

```python
AskUserQuestion(...)  # Hook fires automatically
```

**Benefits:**
- ✅ Guaranteed to fire for every question
- ✅ Single source of truth (UI)
- ✅ Per-project customization via hook scripts
- ✅ Can integrate with external systems

## Alternative Approaches Considered

### 1. Extend permission_prompt Hook

Add question data to existing `permission_prompt` event.

**Rejected because:**
- Overloads permission_prompt with different semantics
- Backward compatibility issues (existing hooks expect tool/description schema)
- PreQuestion and permission_prompt serve different purposes

### 2. Post-Question Hook

Fire hook after user answers question.

**Rejected because:**
- Doesn't solve the voicemode announcement problem
- User needs to hear question BEFORE answering

### 3. Claude Behavior Only (Current Workaround)

Rely on Claude's CLAUDE.md instructions to call voicemode.

**Rejected because:**
- Not guaranteed (Claude may forget or prioritize differently)
- Can't customize per-project
- No integration possibilities

## Request

Please add the `PreQuestion` hook type to Claude Code with the schema and behavior described above.

This would enable:
- Natural voice announcements for accessibility
- Custom question handling workflows
- Better integration with external tools
- Consistent, reliable behavior

## References

- **Related hooks**: `Stop`, `Notification/permission_prompt`, `Notification/idle_prompt`
- **Existing implementation**: `.claude/hooks/permission-request.sh` (similar pattern)
- **Documentation**: AGENT-SETUP.md, REPOSITORY-CONFIG.md

## Contact

Created as part of claude-voicemode project demonstrating voice integration with Claude Code.

Repository: `/Users/shawn/proj/claude-voicemode`
