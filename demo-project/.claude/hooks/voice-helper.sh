#!/bin/bash
# Voice Helper - Get project-specific voice from .voice file
#
# Usage:
#   source "$(dirname "$0")/voice-helper.sh"
#   voicemode converse -m "message" --voice "$VOICE" --no-wait

# Get voice from .voice file or default to af_sky
get_voice() {
    VOICE_FILE="$(git rev-parse --show-toplevel 2>/dev/null || echo '.')/.voice"

    if [ -f "$VOICE_FILE" ]; then
        cat "$VOICE_FILE"
    else
        echo "af_sky"  # default
    fi
}

VOICE=$(get_voice)
