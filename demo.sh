#!/bin/bash
# Demo Script for Claude Voice Mode Hooks
# This script demonstrates all three hook types:
# 1. Task completion (Stop hook)
# 2. Idle notification (Notification/idle_prompt hook)
# 3. Permission request (Notification/permission_prompt hook)

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m' # No Color

DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/demo-project"

echo -e "${BOLD}${BLUE}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║   Claude Voice Mode Hooks - Interactive Demo                 ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo "This demo will showcase three voice notification types:"
echo ""
echo -e "  ${GREEN}1. Task Completion${NC}        - Hear a summary when tasks finish"
echo -e "  ${YELLOW}2. Idle Notification${NC}      - Get reminded after 60 seconds of idle time"
echo -e "  ${BLUE}3. Permission Request${NC}     - Voice announces what Claude is waiting to do"
echo ""
echo "Make sure your speakers are on and volume is up!"
echo ""
read -p "Press Enter to start the demo..."

# Create demo project
echo ""
echo -e "${BOLD}Setting up demo project...${NC}"
rm -rf "$DEMO_DIR"
mkdir -p "$DEMO_DIR/.claude/hooks"
cd "$DEMO_DIR"

# Copy hooks to demo project
cp -r /Users/shawn/proj/claude-voicemode/.claude/hooks/*.sh .claude/hooks/
chmod +x .claude/hooks/*.sh

# Copy settings
cp /Users/shawn/proj/claude-voicemode/.claude/settings.json .claude/

# Create a simple demo app
cat > main.py << 'EOF'
#!/usr/bin/env python3
"""A simple demo app for testing"""

def greet(name):
    return f"Hello, {name}!"

def main():
    names = ["World", "Claude", "Voice Mode"]
    for name in names:
        print(greet(name))

if __name__ == "__main__":
    main()
EOF

# Create a test file
cat > test_main.py << 'EOF'
#!/usr/bin/env python3
"""Tests for demo app"""

import unittest
from main import greet

class TestMain(unittest.TestCase):
    def test_greet(self):
        self.assertEqual(greet("World"), "Hello, World!")
        self.assertEqual(greet("Claude"), "Hello, Claude!")

if __name__ == "__main__":
    unittest.main()
EOF

echo -e "${GREEN}Demo project created at: $DEMO_DIR${NC}"
echo ""
echo ""
read -p "Press Enter to continue to demo scenarios..."

# Clear screen and show demo menu
clear
echo -e "${BOLD}${BLUE}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║              Demo Scenarios - Choose One                      ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo -e "${BOLD}Available Demo Commands (run these in Claude):${NC}"
echo ""
echo -e "  ${GREEN}Demo 1 - Task Completion:${NC}"
echo -e "    ${BOLD}cd $DEMO_DIR && python3 main.py${NC}"
echo -e "    → You'll hear: 'Done: Run the main script' when complete"
echo ""
echo -e "  ${GREEN}Demo 2 - Multiple Tasks:${NC}"
echo -e "    ${BOLD}cd $DEMO_DIR && python3 -m pytest test_main.py -v${NC}"
echo -e "    → You'll hear: 'Done: 2 tasks. Last: Run tests...'"
echo ""
echo -e "  ${GREEN}Demo 3 - Permission Request:${NC}"
echo -e "    ${BOLD}cd $DEMO_DIR && echo 'test' > /etc/hosts${NC}"
echo -e "    → You'll hear: 'I am waiting for permission to Write test to...'"
echo ""
echo -e "  ${YELLOW}Demo 4 - Idle Notification:${NC}"
echo -e "    ${BOLD}cd $DEMO_DIR && echo 'waiting...' && sleep 70${NC}"
echo -e "    → After 60+ seconds you'll hear: 'I am waiting for...'"
echo ""
echo ""
echo -e "${BOLD}${BLUE}Quick Demo - All in One:${NC}"
echo "  Run this in Claude to see all hooks in sequence:"
echo ""
echo -e "  ${BOLD}cd $DEMO_DIR && python3 main.py && echo 'Now wait 65 seconds for idle notification...' && sleep 65${NC}"
echo ""
echo ""
echo -e "${YELLOW}Tips for your screen recording:${NC}"
echo "  • Make sure voicemode services are running: voicemode service status"
echo "  • Speak clearly when explaining each demo"
echo "  • Pause after each command to let the voice play"
echo "  • For idle demo, you can speed up the video during the wait"
echo ""
