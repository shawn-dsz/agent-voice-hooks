#!/bin/bash
# Claude Code Hook: Notify when waiting for permission
# Triggered by PermissionRequest event when a permission dialog is shown

# Get tool info from stdin
INPUT=$(cat)

# Extract the tool name
TOOL=$(echo "$INPUT" | python3 -c "import json,sys; data=json.load(sys.stdin); print(data.get('tool','unknown'))" 2>/dev/null)

# Announce permission request via voicemode
voicemode converse -m "Claude needs permission to use $TOOL" --no-wait
