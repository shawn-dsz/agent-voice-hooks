#!/bin/bash
# Claude Code Hook: Notify when waiting for user input (idle)
# Triggered by Notification event with idle_prompt matcher after 60+ seconds

# Read stdin JSON to get transcript path
INPUT=$(cat)
TRANSCRIPT_PATH=$(echo "$INPUT" | python3 -c "import json,sys; data=json.load(sys.stdin); print(data.get('transcript_path',''))" 2>/dev/null)

# Get project name from directory
PROJECT_NAME=$(basename "$(pwd)")

# Get git branch if in a git repo
GIT_BRANCH=$(git branch --show-current 2>/dev/null)
if [ -n "$GIT_BRANCH" ]; then
    BRANCH_INFO=" on branch ${GIT_BRANCH}"
else
    BRANCH_INFO=""
fi

# Default message
MESSAGE="I am waiting for your next instruction for ${PROJECT_NAME}${BRANCH_INFO}"

# Try to get last user message from transcript
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    LAST_MESSAGE=$(tail -20 "$TRANSCRIPT_PATH" | python3 -c "
import json, sys
for line in sys.stdin:
    try:
        data = json.loads(line.strip())
        if data.get('role') == 'user' and 'content' in data:
            content = data['content']
            if isinstance(content, str) and len(content) > 0:
                # Clean up: truncate if too long, remove newlines
                content = content.replace('\n', ' ').strip()
                if len(content) > 100:
                    content = content[:97] + '...'
                print(content)
                break
    except: pass
" 2>/dev/null)

    if [ -n "$LAST_MESSAGE" ]; then
        MESSAGE="I am waiting for ${LAST_MESSAGE}"
    fi
fi

# Announce waiting for input via voicemode
voicemode converse -m "$MESSAGE" --no-wait
