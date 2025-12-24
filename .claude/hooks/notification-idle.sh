#!/bin/bash
# Claude Code Hook: Notify when waiting for user input (idle)
# Triggered by Notification event with idle_prompt matcher after 60+ seconds

# Get project name from directory
PROJECT_NAME=$(basename "$(pwd)")

# Announce waiting for input with project name
voicemode converse -m "I am waiting for your instruction for ${PROJECT_NAME}" --no-wait
