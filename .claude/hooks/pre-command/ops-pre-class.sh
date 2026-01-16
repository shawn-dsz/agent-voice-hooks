#!/bin/bash
# Operations Management - Pre-Class Reminder Hook
# Triggers on Tuesday and Wednesday before class

# Get current day of week (1-7, where 1 is Monday)
DAY_OF_WEEK=$(date +%u)
HOUR=$(date +%H)

# Wednesday class day (3) before 4pm (16:00)
if [ "$DAY_OF_WEEK" -eq 3 ] && [ "$HOUR" -lt 16 ]; then
    cat << "EOF"

╔════════════════════════════════════════════════════════════╗
║           📚 OPERATIONS MANAGEMENT - CLASS TODAY          ║
╠════════════════════════════════════════════════════════════╣
║
║  ⏰  Class: 6:00pm - 9:15pm today
║  📍  Location: Face-to-Face
║  👨‍🏫  Lecturer: Young-San Lin
║
║  PRE-CLASS CHECKLIST:
║  ☐  Review case analysis one more time
║  ☐  Prepare 2-3 discussion points
║  ☐  Check Canvas for announcements
║  ☐  Note questions to ask in class
║  ☐  Bring calculator (if needed)
║
║  Remember: Participation = 30% of grade! Speak up!
║
╚════════════════════════════════════════════════════════════╝

EOF
fi

# Tuesday (day 2) - reminder to prep for tomorrow
if [ "$DAY_OF_WEEK" -eq 2 ]; then
    cat << "EOF"

╔════════════════════════════════════════════════════════════╗
║        📖 OPERATIONS MANAGEMENT - PREP FOR TOMORROW       ║
╠════════════════════════════════════════════════════════════╣
║
║  ⏰  Class is TOMORROW (Wednesday 6pm)
║
║  TONIGHT'S TASKS:
║  ☐  Complete case analysis
║  ☐  Prepare discussion points
║  ☐  Review lecture slides
║  ☐  Identify questions for class
║
║  Use: /prep-case to help structure your analysis!
║
╚════════════════════════════════════════════════════════════╝

EOF
fi
