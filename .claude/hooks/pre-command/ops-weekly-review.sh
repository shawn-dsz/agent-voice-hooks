#!/bin/bash
# Operations Management - Weekly Review Reminder
# Triggers on Sunday evening

# Get current day of week (1-7, where 1 is Monday)
DAY_OF_WEEK=$(date +%u)
HOUR=$(date +%H)

# Sunday (day 7) evening (6pm or later)
if [ "$DAY_OF_WEEK" -eq 7 ] && [ "$HOUR" -ge 18 ]; then
    cat << "EOF"

╔════════════════════════════════════════════════════════════╗
║          📊 WEEKLY REVIEW - Plan for Next Week            ║
╠════════════════════════════════════════════════════════════╣
║
║  WEEKLY CHECK-IN:
║  ☐  Did I complete all readings this week?
║  ☐  Do I understand this week's concepts?
║  ☐  Have I reviewed and consolidated my notes?
║  ☐  Do I have questions for next class?
║  ☐  Am I prepared for next week's topics?
║
║  TASKS FOR TONIGHT:
║  ☐  Review all notes from the week
║  ☐  Practice problems from this week's topic
║  ☐  Connect this week's topics to previous weeks
║  ☐  Plan next week's study schedule
║  ☐  Note any areas of weakness to address
║
║  Use: /review-week to consolidate your learning!
║
║  UPCOMING:
║  • TA Session: Saturday 1pm (if next week has one)
║  • Class: Wednesday 6pm
║
╚════════════════════════════════════════════════════════════╝

EOF
fi
