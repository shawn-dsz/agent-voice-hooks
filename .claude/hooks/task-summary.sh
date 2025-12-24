#!/bin/bash
# Claude Code Stop Hook: Announce completed tasks summary
# Reads the most recent todo file and generates a ~10 word summary

TODO_DIR="$HOME/.claude/todos"

# Find the most recently modified todo file
LATEST_TODO=$(ls -t "$TODO_DIR"/*.json 2>/dev/null | head -1)

if [ -z "$LATEST_TODO" ]; then
    # No todo file found, use default message
    voicemode converse -m "Task completed. Ready for next instructions." --no-wait
    exit 0
fi

# Extract completed tasks from the todo file and generate summary
MESSAGE=$(python3 - "
import json

try:
    with open('$LATEST_TODO', 'r') as f:
        todos = json.load(f)

    completed = [t.get('content', '') for t in todos if t.get('status') == 'completed']

    if not completed:
        print('Task completed. Ready for next instructions.')
    elif len(completed) == 1:
        # Single task - use it directly, truncate to 8 words
        words = completed[0].split()
        if len(words) > 8:
            print('Done: ' + ' '.join(words[:8]) + '...')
        else:
            print('Done: ' + completed[0])
    else:
        # Multiple tasks - use the most recent (last in list)
        words = completed[-1].split()
        if len(words) > 8:
            print(f'Done: {len(completed)} tasks. Last: ' + ' '.join(words[:8]) + '...')
        else:
            print(f'Done: {len(completed)} tasks. Last: ' + completed[-1])
except Exception:
    print('Task completed. Ready for next instructions.')
" 2>/dev/null)

# Announce via voicemode
voicemode converse -m "$MESSAGE" --no-wait
