#!/bin/bash

# Pre-Question Hook - Proof of Concept
#
# This hook script demonstrates what the PreQuestion hook would do
# when/if Claude Code adds support for it.
#
# CURRENT STATUS: Non-functional (requires Claude Code core support)
#
# Expected event data (via stdin):
# {
#   "tool": "AskUserQuestion",
#   "question": "What real-time technology would you prefer?",
#   "header": "Real-time tech",
#   "multiSelect": false,
#   "options": [
#     {
#       "label": "Server-Sent Events (SSE)",
#       "description": "One-way server-to-client streaming..."
#     },
#     ...
#   ]
# }

set -e

# Read JSON from stdin
INPUT=$(cat)

# Extract question text
QUESTION=$(echo "$INPUT" | python3 -c "
import json
import sys

try:
    data = json.load(sys.stdin)
    print(data.get('question', 'Unknown question'))
except Exception as e:
    print('Error parsing question', file=sys.stderr)
    sys.exit(1)
")

# Extract and format options
OPTIONS=$(echo "$INPUT" | python3 -c "
import json
import sys

try:
    data = json.load(sys.stdin)
    options = data.get('options', [])

    if not options:
        print('')
        sys.exit(0)

    # Build natural language list of options
    parts = []
    for i, opt in enumerate(options):
        label = opt.get('label', f'Option {i+1}')
        parts.append(f'Option {i+1} is {label}')

    # Join with commas and 'or'
    if len(parts) == 1:
        print(parts[0])
    elif len(parts) == 2:
        print(f'{parts[0]} or {parts[1]}')
    else:
        print(', '.join(parts[:-1]) + f', or {parts[-1]}')

except Exception as e:
    print('', file=sys.stderr)
    sys.exit(0)
")

# Build the message
if [ -n "$OPTIONS" ]; then
    MESSAGE="$QUESTION $OPTIONS."
else
    MESSAGE="$QUESTION"
fi

# Announce via voicemode
# Using --no-wait because the user will respond via the UI, not voice
voicemode converse -m "$MESSAGE" --no-wait

exit 0
