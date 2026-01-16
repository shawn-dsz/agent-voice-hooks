#!/bin/bash
# Operations Management - TA Session Reminder
# Triggers on Saturday before 1pm

# Get current day of week (1-7, where 1 is Monday)
DAY_OF_WEEK=$(date +%u)
HOUR=$(date +%H)

# Saturday (day 6) before 11am (gives time to prep)
if [ "$DAY_OF_WEEK" -eq 6 ] && [ "$HOUR" -lt 11 ]; then
    cat << "EOF"

╔════════════════════════════════════════════════════════════╗
║             🎓 TA SESSION TODAY - 1:00pm                   ║
╠════════════════════════════════════════════════════════════╣
║
║  👨‍💼  TA: Braden Moore
║  ⏰  Time: 1:00pm - 3:00pm
║  📋  Topic: Problem Set walkthrough
║
║  PREP CHECKLIST:
║  ☐  Review Problem Set for this week
║  ☐  Note questions you want to ask
║  ☐  Attempt all problems first (even if stuck)
║  ☐  Bring calculator
║  ☐  Bring your attempted work (shows thought process)
║
║  Use: /ta-questions to prepare specific questions!
║
║  Location: Check Canvas for details
║  Link: https://mbsedu.instructure.com/courses/4956/pages/ta-session-details
║
╚════════════════════════════════════════════════════════════╝

EOF
fi
