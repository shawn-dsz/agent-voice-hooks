#!/bin/bash
# Claude Code Hook: Notify when waiting for user input (idle)
# Triggered by Notification event with idle_prompt matcher after 60+ seconds

# Announce waiting for input via voicemode
voicemode converse -m "Claude is waiting for your input" --no-wait
