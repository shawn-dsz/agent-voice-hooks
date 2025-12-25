#!/bin/bash
# Claude Code Hook: Notify when waiting for permission
# Triggered by PermissionRequest event when a permission dialog is shown

# Get tool info from stdin
INPUT=$(cat)

# Extract the tool name and description
TOOL=$(echo "$INPUT" | python3 -c "import json,sys; data=json.load(sys.stdin); print(data.get('tool','unknown'))" 2>/dev/null)
DESC=$(echo "$INPUT" | python3 -c "import json,sys; data=json.load(sys.stdin); print(data.get('description',''))" 2>/dev/null)

# Get project context
PROJECT_NAME=$(basename "$(pwd)")
GIT_BRANCH=$(git branch --show-current 2>/dev/null)

# Build context suffix (project + branch if not main)
CONTEXT="with $PROJECT_NAME"
if [ -n "$GIT_BRANCH" ] && [ "$GIT_BRANCH" != "main" ]; then
    CONTEXT="$CONTEXT on branch $GIT_BRANCH"
fi

# Build message with description if available
if [ "$TOOL" = "AskUserQuestion" ]; then
    # Special case for AskUserQuestion - user-friendly message
    MESSAGE="I am waiting for your input $CONTEXT"
elif [ -n "$DESC" ]; then
    # Remove "Bash" prefix from description if present (e.g., "Bash command: " -> "")
    # Handles: "Bash command: ", "Bash command ", "Bash: ", "Bash "
    CLEAN_DESC=$(echo "$DESC" | sed -E 's/^Bash( command)?[ :]+ ?//')
    MESSAGE="I am waiting for permission to $CLEAN_DESC"
elif [ -n "$TOOL" ] && [ "$TOOL" != "unknown" ]; then
    MESSAGE="I am waiting for permission to use $TOOL"
else
    # No tool or description available - generic message
    MESSAGE="I am waiting for your permission $CONTEXT"
fi

# Announce permission request via voicemode
voicemode converse -m "$MESSAGE" --no-wait
