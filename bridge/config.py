"""Configuration module for Kimi Voice Hooks.

Handles loading and merging configuration from multiple sources:
1. Global defaults (hardcoded)
2. Global config (~/.config/kimi-voice/config.toml)
3. Project config (.kimi-voice.toml in cwd)
4. .voice file (simple text file with voice name, Claude compatibility)
5. Environment variables (optional override)
"""

from __future__ import annotations

import os
import sys
from dataclasses import dataclass, field, fields
from pathlib import Path
from typing import Any

# TOML parsing: use tomllib for Python 3.11+, tomli for older versions
if sys.version_info >= (3, 11):
    import tomllib
else:
    try:
        import tomli as tomllib
    except ImportError:
        tomllib = None  # type: ignore


@dataclass
class Config:
    """Configuration for Kimi Voice Hooks.
    
    Attributes:
        tts_backend: TTS backend to use ("voicemode", "say", "kokoro", "openai")
        voice: Voice identifier (specific to backend)
        speed: Speech rate multiplier (1.0 = normal)
        idle_timeout: Seconds before idle announcement
        idle_enabled: Whether idle announcements are enabled
        announce_turn_end: Speak on task completion
        announce_approval: Speak on permission requests
        announce_idle: Speak on idle timeout
        announce_errors: Speak on errors/interruptions
        kimi_command: Path to kimi binary
        extra_args: Additional arguments to pass to kimi --wire
    """
    # Voice settings
    tts_backend: str = "voicemode"
    voice: str = "af_sky"
    speed: float = 1.0
    
    # Idle detection
    idle_timeout: int = 60
    idle_enabled: bool = True
    
    # Event announcements
    announce_turn_end: bool = True
    announce_approval: bool = True
    announce_idle: bool = True
    announce_errors: bool = False
    
    # Bridge settings
    kimi_command: str = "kimi"
    extra_args: list[str] = field(default_factory=list)
    
    # Track which fields were explicitly set (for proper merging)
    _explicitly_set: set[str] = field(default_factory=set, repr=False, compare=False)
    
    def __post_init__(self):
        """Ensure _explicitly_set is initialized."""
        if not hasattr(self, '_explicitly_set') or self._explicitly_set is None:
            object.__setattr__(self, '_explicitly_set', set())
    
    # Field name mappings from TOML keys to dataclass field names
    # Maps TOML section.key to dataclass field name
    _FIELD_MAPPINGS = {
        'backend': 'tts_backend',
    }
    
    # Section prefixes for fields that need them (e.g., idle.timeout -> idle_timeout)
    # These are fields where the TOML key alone doesn't match the dataclass field name
    _SECTION_PREFIXES = {
        'idle': ['timeout', 'enabled'],
    }
    
    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> Config:
        """Create Config from dictionary, handling nested sections."""
        flat_data: dict[str, Any] = {}
        explicitly_set_fields: set[str] = set()
        
        # Flatten nested sections (voice.*, idle.*, events.*, bridge.*)
        for section_name, section_data in data.items():
            if isinstance(section_data, dict):
                for key, value in section_data.items():
                    # Apply section prefixes for fields that need them
                    if section_name in cls._SECTION_PREFIXES and key in cls._SECTION_PREFIXES[section_name]:
                        flat_key = f"{section_name}_{key}"
                    else:
                        flat_key = key
                    flat_data[flat_key] = value
                    explicitly_set_fields.add(flat_key)
            else:
                flat_data[section_name] = section_data
                explicitly_set_fields.add(section_name)
        
        # Apply field name mappings
        mapped_data: dict[str, Any] = {}
        mapped_fields: set[str] = set()
        for key, value in flat_data.items():
            mapped_key = cls._FIELD_MAPPINGS.get(key, key)
            mapped_data[mapped_key] = value
            if key in explicitly_set_fields:
                mapped_fields.add(mapped_key)
        
        # Only include fields that exist in the dataclass
        valid_fields = {f.name for f in fields(cls) if not f.name.startswith('_')}
        filtered_data = {k: v for k, v in mapped_data.items() if k in valid_fields}
        
        # Create config and track explicitly set fields
        config = cls(**filtered_data)
        object.__setattr__(config, '_explicitly_set', set(filtered_data.keys()))
        return config
    
    def _is_explicitly_set(self, field_name: str) -> bool:
        """Check if a field was explicitly set in this config."""
        if hasattr(self, '_explicitly_set') and field_name in self._explicitly_set:
            return True
        # If _explicitly_set is empty (direct construction), check if value differs from default
        val = getattr(self, field_name)
        field = next((f for f in fields(self) if f.name == field_name), None)
        if field:
            return val != field.default
        return False
    
    def merge(self, other: Config) -> Config:
        """Merge another config into this one, with other taking precedence.
        
        Only fields explicitly set in 'other' will override self.
        """
        result = Config()
        
        # Track all explicitly set fields from both configs
        explicitly_set: set[str] = set()
        for f in fields(self):
            if f.name.startswith('_'):
                continue
            if self._is_explicitly_set(f.name):
                explicitly_set.add(f.name)
            if other._is_explicitly_set(f.name):
                explicitly_set.add(f.name)
        
        for f in fields(self):
            if f.name.startswith('_'):
                continue
            other_val = getattr(other, f.name)
            self_val = getattr(self, f.name)
            # Use other's value if it was explicitly set
            if other._is_explicitly_set(f.name):
                setattr(result, f.name, other_val)
            else:
                setattr(result, f.name, self_val)
        
        object.__setattr__(result, '_explicitly_set', explicitly_set)
        return result
    
    def to_dict(self) -> dict[str, dict[str, Any]]:
        """Convert Config to nested dictionary format for TOML."""
        return {
            "voice": {
                "backend": self.tts_backend,
                "voice": self.voice,
                "speed": self.speed,
            },
            "idle": {
                "timeout": self.idle_timeout,
                "enabled": self.idle_enabled,
            },
            "events": {
                "announce_turn_end": self.announce_turn_end,
                "announce_approval": self.announce_approval,
                "announce_idle": self.announce_idle,
                "announce_errors": self.announce_errors,
            },
            "bridge": {
                "kimi_command": self.kimi_command,
                "extra_args": self.extra_args,
            },
        }


def get_global_config_path() -> Path:
    """Get the path to the global config file."""
    # Check XDG_CONFIG_HOME first, then fall back to ~/.config
    config_home = os.environ.get("XDG_CONFIG_HOME")
    if config_home:
        return Path(config_home) / "kimi-voice" / "config.toml"
    return Path.home() / ".config" / "kimi-voice" / "config.toml"


def get_project_config_path() -> Path:
    """Get the path to the project config file in current directory."""
    return Path.cwd() / ".kimi-voice.toml"


def get_voice_file_path() -> Path:
    """Get the path to the .voice file in current directory."""
    return Path.cwd() / ".voice"


def load_toml_file(path: Path) -> dict[str, Any]:
    """Load a TOML file, returning empty dict if not found or error."""
    if not path.exists():
        return {}
    
    if tomllib is None:
        raise ImportError(
            "TOML parsing requires Python 3.11+ or 'tomli' package. "
            "Install with: pip install tomli"
        )
    
    try:
        with open(path, "rb") as f:
            return tomllib.load(f)
    except Exception as e:
        print(f"Warning: Failed to load config from {path}: {e}", file=sys.stderr)
        return {}


def load_voice_file(path: Path) -> dict[str, str]:
    """Load .voice file, returning voice setting if found.
    
    The .voice file is a simple text file containing just the voice name,
    for compatibility with Claude voice hooks.
    """
    if not path.exists():
        return {}
    
    try:
        content = path.read_text().strip()
        if content:
            return {"voice": content}
    except Exception as e:
        print(f"Warning: Failed to load .voice file from {path}: {e}", file=sys.stderr)
    
    return {}


def load_env_overrides() -> dict[str, Any]:
    """Load configuration overrides from environment variables.
    
    Environment variables:
    - KIMI_VOICE_TTS_BACKEND
    - KIMI_VOICE_VOICE
    - KIMI_VOICE_SPEED
    - KIMI_VOICE_IDLE_TIMEOUT
    - KIMI_VOICE_IDLE_ENABLED
    - KIMI_VOICE_ANNOUNCE_TURN_END
    - KIMI_VOICE_ANNOUNCE_APPROVAL
    - KIMI_VOICE_ANNOUNCE_IDLE
    - KIMI_VOICE_ANNOUNCE_ERRORS
    - KIMI_VOICE_KIMI_COMMAND
    """
    env_mapping = {
        "KIMI_VOICE_TTS_BACKEND": "tts_backend",
        "KIMI_VOICE_VOICE": "voice",
        "KIMI_VOICE_SPEED": "speed",
        "KIMI_VOICE_IDLE_TIMEOUT": "idle_timeout",
        "KIMI_VOICE_IDLE_ENABLED": "idle_enabled",
        "KIMI_VOICE_ANNOUNCE_TURN_END": "announce_turn_end",
        "KIMI_VOICE_ANNOUNCE_APPROVAL": "announce_approval",
        "KIMI_VOICE_ANNOUNCE_IDLE": "announce_idle",
        "KIMI_VOICE_ANNOUNCE_ERRORS": "announce_errors",
        "KIMI_VOICE_KIMI_COMMAND": "kimi_command",
    }
    
    overrides: dict[str, Any] = {}
    for env_var, config_key in env_mapping.items():
        value = os.environ.get(env_var)
        if value is not None:
            # Convert string values to appropriate types
            if config_key in ("speed",):
                try:
                    overrides[config_key] = float(value)
                except ValueError:
                    print(f"Warning: Invalid float value for {env_var}: {value}", file=sys.stderr)
            elif config_key in ("idle_timeout",):
                try:
                    overrides[config_key] = int(value)
                except ValueError:
                    print(f"Warning: Invalid int value for {env_var}: {value}", file=sys.stderr)
            elif config_key in ("idle_enabled", "announce_turn_end", "announce_approval", 
                               "announce_idle", "announce_errors"):
                overrides[config_key] = value.lower() in ("true", "1", "yes", "on")
            else:
                overrides[config_key] = value
    
    return overrides


def load_config(
    global_path: Path | None = None,
    project_path: Path | None = None,
    voice_path: Path | None = None,
    use_env: bool = True,
) -> Config:
    """Load and merge configuration from all sources.
    
    Loading order (later sources override earlier ones):
    1. Hardcoded defaults
    2. Global config (~/.config/kimi-voice/config.toml)
    3. Project config (.kimi-voice.toml in cwd)
    4. .voice file (simple voice name)
    5. Environment variables (optional)
    
    Args:
        global_path: Override path to global config file
        project_path: Override path to project config file
        voice_path: Override path to .voice file
        use_env: Whether to apply environment variable overrides
    
    Returns:
        Merged Config instance
    """
    # Start with defaults
    config = Config()
    
    # 2. Load global config
    global_config_path = global_path or get_global_config_path()
    global_data = load_toml_file(global_config_path)
    if global_data:
        config = config.merge(Config.from_dict(global_data))
    
    # 3. Load project config
    project_config_path = project_path or get_project_config_path()
    project_data = load_toml_file(project_config_path)
    if project_data:
        config = config.merge(Config.from_dict(project_data))
    
    # 4. Load .voice file (compatibility with Claude voice hooks)
    voice_file_path = voice_path or get_voice_file_path()
    voice_data = load_voice_file(voice_file_path)
    if voice_data:
        config = config.merge(Config.from_dict({"voice": voice_data}))
    
    # 5. Apply environment variable overrides
    if use_env:
        env_data = load_env_overrides()
        if env_data:
            config = config.merge(Config.from_dict(env_data))
    
    return config


def create_default_config(path: Path | None = None) -> None:
    """Create a default configuration file if it doesn't exist.
    
    Args:
        path: Path to create config at, defaults to global config location
    """
    config_path = path or get_global_config_path()
    
    if config_path.exists():
        return
    
    # Create directory if needed
    config_path.parent.mkdir(parents=True, exist_ok=True)
    
    default_content = '''# Kimi Voice Hooks Configuration
# https://github.com/yourusername/kimi-voice-hooks

[voice]
# TTS backend: "voicemode", "say", "kokoro", or "openai"
backend = "voicemode"

# Voice identifier (backend-specific)
# See voices.toml for available presets
voice = "af_sky"

# Speech rate (1.0 = normal speed)
speed = 1.0

[idle]
# Seconds of inactivity before idle announcement
timeout = 60

# Enable idle announcements
enabled = true

[events]
# Announce task completion
announce_turn_end = true

# Announce permission requests
announce_approval = true

# Announce idle timeout
announce_idle = true

# Announce errors and interruptions
announce_errors = false

[bridge]
# Path to kimi binary
kimi_command = "kimi"

# Additional arguments to pass to kimi --wire
# Example: ["--model", "kimi-k2"]
extra_args = []
'''
    
    config_path.write_text(default_content)
    print(f"Created default config at: {config_path}")


# Convenience function for testing
def get_config() -> Config:
    """Get the current configuration, loading from all sources."""
    return load_config()
