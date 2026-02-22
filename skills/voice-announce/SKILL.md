---
name: voice-announce
description: Voice announcement behaviour for task completions and user interactions
tools:
  - voicemode
tags:
  - voice
  - notifications
  - announcements
---

# Voice Announcements

You have access to a `voicemode` MCP tool that can speak messages aloud.
Use it in these situations to provide an audio notification experience
similar to Claude Code's native hooks.

## When to Announce

### 1. Task Completion
After completing a significant task or making substantial progress, call voicemode
to announce a brief (~10 word) summary of what was done.

**Examples:**
- "Done: refactored the authentication module"
- "Created 5 files for the new API endpoint"
- "Fixed the routing bug in navigation"
- "Tests passing, build successful"

### 2. Before Asking Questions
When you are about to ask the user a question that requires their decision
or has multiple options, first announce the question via voicemode so the
user hears the context even if they're not watching the screen.

**Examples:**
- "Which database would you prefer, Postgres or SQLite?"
- "Should I commit these changes now?"
- "Found 3 matching files, which one should I edit?"

### 3. Errors Requiring Guidance
When you encounter an error you cannot resolve automatically and need user
input to proceed, announce it via voicemode.

**Examples:**
- "Build failed with 3 errors, need your guidance"
- "Permission denied, please check credentials"
- "Test suite failed, shall I continue?"

### 4. Long-Running Operations Complete
When a task takes more than 30 seconds to complete, announce completion.

**Examples:**
- "Migration completed successfully"
- "Dependencies installed"
- "Docker container is ready"

## How to Announce

Call the voicemode MCP tool with:

```json
{
  "message": "Your brief announcement here",
  "wait_for_response": false
}
```

**Guidelines:**
- **Message length**: Keep it brief, 10 words maximum for most announcements
- **wait_for_response**: Set to `false` for announcements, `true` only when you need voice input back
- **Tone**: Professional but friendly, actionable information first

## When NOT to Announce

Do NOT use voicemode in these situations:

- **Every tool call**: Do not announce each file read, search, or shell command
- **Intermediate steps**: Do not announce each step in a multi-step task
- **Active typing**: Do not announce when the user is actively engaged (recent TurnBegin)
- **Rapid-fire outputs**: If multiple messages occur within 2 seconds, only announce the last one
- **Expected confirmations**: Simple "Done" or "OK" responses don't need voice
- **Silent operations**: Background tasks the user didn't explicitly request

## Examples of Good Announcements

| Situation | Good Announcement |
|-----------|-------------------|
| Refactoring complete | "Refactored auth module, all tests passing" |
| Need user choice | "Which database would you prefer?" |
| Build failure | "Build failed, need your guidance" |
| File creation | "Created 3 new component files" |
| Waiting for input | "Waiting for your next instruction" |

## Examples of Poor Announcements

| Situation | Poor Announcement | Why |
|-----------|-------------------|-----|
| Read a file | "Reading file src/index.js" | Too granular |
| Simple ack | "OK" | No information |
| Every step | "Step 1 of 5 complete" | Too noisy |
| Error details | "Error E404 at line 42 column 3..." | Too verbose for voice |

## Integration with Wire Bridge

When running via `kimi-voice` (the Wire bridge), the bridge handles:
- Automatic task completion announcements on TurnEnd
- Permission request announcements on ApprovalRequest
- Idle timeout announcements

You should STILL use voicemode for:
- Conversational context (questions, choices)
- Custom completion messages beyond the default summary
- Error notifications the bridge doesn't catch
