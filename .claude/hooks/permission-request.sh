#!/bin/bash
# Claude Code Hook: Notify when waiting for permission
# Triggered by PermissionRequest event when a permission dialog is shown

# Get tool info from stdin
INPUT=$(cat)

# Extract the tool name and description
TOOL=$(echo "$INPUT" | python3 -c "import json,sys; data=json.load(sys.stdin); print(data.get('tool','unknown'))" 2>/dev/null)
DESC=$(echo "$INPUT" | python3 -c "import json,sys; data=json.load(sys.stdin); print(data.get('description',''))" 2>/dev/null)

# Build message with description if available
if [ -n "$DESC" ]; then
    # Remove "Bash" prefix from description if present (e.g., "Bash command: " -> "")
    # Handles: "Bash command: ", "Bash command ", "Bash: ", "Bash "
    CLEAN_DESC=$(echo "$DESC" | sed -E 's/^Bash( command)?[ :]+ ?//')
    MESSAGE="Claude is waiting to $CLEAN_DESC"
else
    MESSAGE="Claude is waiting to use $TOOL"
fi

# Announce permission request via voicemode
voicemode converse -m "$MESSAGE" --no-wait
