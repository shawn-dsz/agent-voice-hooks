# Development Setup Guide: Kimi Voice Hooks

Step-by-step instructions for setting up a development environment for Kimi Voice Hooks.

> **Note:** This guide is for contributors and developers who want to modify or extend Kimi Voice Hooks.

---

## Prerequisites

Before starting, verify:
- You are on macOS or Linux (Windows/WSL not fully supported)
- Python 3.10+ is installed (`python3 --version`)
- Kimi Code CLI is installed (`kimi --version`)
- Git is installed

---

## Quick Setup

```bash
# Clone the repository
git clone https://github.com/yourusername/kimi-voice-hooks.git
cd kimi-voice-hooks

# Install in development mode
./install.sh

# Verify installation
~/.local/bin/kimi-voice --version
```

---

## Development Installation

### Step 1: Clone and Setup

```bash
# Clone the repo
git clone https://github.com/yourusername/kimi-voice-hooks.git
cd kimi-voice-hooks

# Create a virtual environment (recommended)
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r bridge/requirements.txt
```

### Step 2: Install in Development Mode

```bash
# Install symlinks instead of copies for live editing
ln -sf "$(pwd)/bridge" ~/.local/share/kimi-voice-dev
ln -sf "$(pwd)/bridge/kimi-voice" ~/.local/bin/kimi-voice-dev
```

Or use the install script with modifications:
```bash
# Standard install (copies files)
./install.sh

# For development, manually symlink:
rm -rf ~/.local/share/kimi-voice
ln -s "$(pwd)/bridge" ~/.local/share/kimi-voice
```

### Step 3: Verify Development Setup

```bash
# Test bridge directly
python3 bridge/bridge.py --help

# Test voice module
python3 bridge/voice.py --info

# Test event handlers
python3 -c "
import sys
sys.path.insert(0, 'bridge')
from events import EventHandler
print('EventHandler imported successfully')
"
```

---

## Project Structure

```
kimi-voice-hooks/
├── install.sh              # One-command installer
├── README.md               # User documentation
├── TROUBLESHOOTING.md      # Troubleshooting guide
├── AGENT-SETUP.md          # This file
├── KIMI-VOICE-HOOKS-PLAN.md # Implementation plan
│
├── bridge/                 # Core bridge implementation
│   ├── __init__.py
│   ├── bridge.py           # Main bridge (async I/O, Wire protocol)
│   ├── events.py           # Event handlers (TurnEnd, ApprovalRequest)
│   ├── voice.py            # TTS backend abstraction
│   ├── idle_tracker.py     # Idle timer logic
│   ├── config.py           # Configuration loading
│   ├── kimi-voice          # CLI entry point (bash wrapper)
│   └── requirements.txt    # Python dependencies
│
├── mcp/                    # MCP registration
│   ├── mcp-config.json     # voicemode MCP config
│   └── install-mcp.sh      # MCP install helper
│
├── skills/                 # Kimi skills
│   └── voice-announce/
│       └── SKILL.md        # Model-driven voice skill
│
├── config/                 # Default configurations
│   ├── kimi-voice.toml     # Default config template
│   └── voices.toml         # Voice presets
│
└── tests/                  # Test suite
    ├── test-voice.sh       # Voice output tests
    └── run-all-tests.sh    # Full test runner
```

---

## Running Tests

### Voice Tests

```bash
# Run voice output tests
./tests/test-voice.sh

# Quick mode (skip actual audio playback)
./tests/test-voice.sh --quick

# With mock TTS (for CI)
./tests/test-voice.sh --mock

# Diagnostics only
./tests/test-voice.sh --diagnostics
```

### Integration Tests

```bash
# Run all tests
./tests/run-all-tests.sh

# Run specific test suites
./tests/run-all-tests.sh --unit
./tests/run-all-tests.sh --integration
```

### Manual Testing

```bash
# Test the bridge with mock Kimi
echo '{"jsonrpc":"2.0","method":"event","params":{"type":"TurnEnd"}}' | \
    python3 bridge/bridge.py

# Test voice backends
python3 bridge/voice.py "Test message" --backend voicemode
python3 bridge/voice.py "Test message" --backend say
python3 bridge/voice.py "Test message" --backend silent
```

---

## How to Contribute

### Making Changes

1. **Create a feature branch:**
   ```bash
   git checkout -b feature/my-feature
   ```

2. **Make your changes** to the relevant files in `bridge/`

3. **Test your changes:**
   ```bash
   # Reload the bridge (if using symlinks)
   ~/.local/bin/kimi-voice "test prompt"
   
   # Or run directly
   python3 bridge/bridge.py "test prompt"
   ```

4. **Run the test suite:**
   ```bash
   ./tests/run-all-tests.sh
   ```

### Code Style

- **Python:** Follow PEP 8
- **Bash:** Use `shellcheck` for shell scripts
- **Type hints:** Use Python type hints for all new code

```bash
# Check Python style
flake8 bridge/
black bridge/

# Check shell scripts
shellcheck install.sh
shellcheck bridge/kimi-voice
```

### Testing Checklist

Before submitting a PR:

- [ ] Code runs without errors on Python 3.10+
- [ ] Type hints are included
- [ ] Tests pass (`./tests/run-all-tests.sh`)
- [ ] New features have tests
- [ ] Documentation is updated
- [ ] CHANGELOG.md is updated (if applicable)

---

## Debugging

### Enable Debug Output

```bash
# Set debug environment variable
export KIMI_VOICE_DEBUG=1

# Run kimi-voice
kimi-voice "test"
```

### Debug Specific Modules

```bash
# Debug config loading
python3 -c "
import sys
sys.path.insert(0, 'bridge')
from config import load_config, get_config_path
print('Config path:', get_config_path())
config = load_config()
print('Config:', config)
"

# Debug voice backends
python3 -c "
import sys
sys.path.insert(0, 'bridge')
from voice import get_backend_info
import json
print(json.dumps(get_backend_info(), indent=2))
"
```

### Trace Wire Protocol

```bash
# Save all Wire protocol messages
kimi --wire 2>&1 | tee wire-log.jsonl

# Or with the bridge
KIMI_VOICE_DEBUG=1 kimi-voice "test" 2>&1 | tee bridge-debug.log
```

---

## Common Development Tasks

### Add a New TTS Backend

1. Edit `bridge/voice.py`:
   ```python
   class TTSBackend(Enum):
       # ... existing backends ...
       NEW_BACKEND = auto()
   
   async def _speak_new_backend(message: str, voice: str) -> None:
       # Implementation here
       pass
   
   # Update speak() function
   async def speak(message: str, config: VoiceConfig | None = None) -> None:
       # ...
       if backend == TTSBackend.NEW_BACKEND:
           await _speak_new_backend(message, cfg.voice)
   ```

2. Update `detect_backend()` if auto-detection is desired

3. Add tests in `tests/test-voice.sh`

4. Update documentation

### Add a New Event Handler

1. Edit `bridge/events.py`:
   ```python
   async def on_new_event(self, payload: dict[str, Any], config: Config) -> None:
       """Handle NewEvent type."""
       # Implementation
   ```

2. Wire it up in `bridge/bridge.py`:
   ```python
   async def _handle_wire_event(...):
       # ...
       elif event_type == "NewEvent":
           await event_handler.on_new_event(payload, config)
   ```

3. Add config option in `bridge/config.py` if needed

### Modify Configuration

1. Edit `bridge/config.py` - add field to `Config` dataclass
2. Update `create_default_config()` in `config.py`
3. Update `config/kimi-voice.toml` template
4. Document in README.md

---

## Release Process

1. **Update version:**
   - Update `VERSION` in `install.sh`
   - Update `VERSION` in `bridge/kimi-voice`

2. **Update CHANGELOG.md:**
   - Document all changes
   - Credit contributors

3. **Run full test suite:**
   ```bash
   ./tests/run-all-tests.sh
   ```

4. **Test clean install:**
   ```bash
   # In a clean environment
   ./install.sh
   kimi-voice "test"
   ```

5. **Create git tag:**
   ```bash
   git tag -a v0.1.0 -m "Release v0.1.0"
   git push origin v0.1.0
   ```

---

## Resources

- **Kimi Wire Protocol:** Run `kimi --wire --help` for protocol details
- **VoiceMode Docs:** https://github.com/yourusername/voice-mode
- **Python asyncio:** https://docs.python.org/3/library/asyncio.html

---

## Agent Checklist (For AI Contributors)

When setting up or modifying this project:

- [ ] Cloned repo and created virtual environment
- [ ] Installed dependencies from `bridge/requirements.txt`
- [ ] Verified `python3 --version` is 3.10+
- [ ] Can run `python3 bridge/bridge.py --help`
- [ ] Can run `python3 bridge/voice.py --info`
- [ ] Tests pass (`./tests/test-voice.sh --quick`)
- [ ] Changes tested with `kimi-voice "test prompt"`
- [ ] Code follows existing style patterns
- [ ] Type hints added for new functions
- [ ] Documentation updated if needed
