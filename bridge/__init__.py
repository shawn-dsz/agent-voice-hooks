"""Kimi Voice Hooks - Wire Bridge Core.

This package provides the core bridge functionality for intercepting
Kimi Code CLI's Wire protocol events and triggering voice announcements.
"""

from __future__ import annotations

from .bridge import run_bridge, main
from .config import Config, load_config
from .events import EventHandler, handle_turn_end, handle_approval_request
from .idle_tracker import IdleTracker, create_idle_tracker
from .voice import speak, VoiceConfig, TTSBackend, detect_backend

__version__ = "0.1.0"

__all__ = [
    # Bridge
    "run_bridge",
    "main",
    # Config
    "Config",
    "load_config",
    # Events
    "EventHandler",
    "handle_turn_end",
    "handle_approval_request",
    # Idle
    "IdleTracker",
    "create_idle_tracker",
    # Voice
    "speak",
    "VoiceConfig",
    "TTSBackend",
    "detect_backend",
]
