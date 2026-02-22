"""Voice output abstraction for Kimi Voice Hooks.

Provides a unified interface for text-to-speech with multiple backend support:
- voicemode: High-quality TTS via voicemode CLI
- say: macOS built-in text-to-speech
- silent: Fallback that logs to stderr (no audio)
"""

from __future__ import annotations

import asyncio
import shutil
import sys
from dataclasses import dataclass
from enum import Enum, auto
from typing import Callable


class TTSBackend(Enum):
    """Available TTS backends in priority order."""
    VOICEMODE = auto()
    SAY = auto()
    SILENT = auto()


@dataclass(frozen=True)
class VoiceConfig:
    """Configuration for voice output.
    
    Attributes:
        backend: TTS backend to use (auto-detected if not specified)
        voice: Voice identifier (backend-specific)
        speed: Speech rate multiplier (1.0 = normal)
        enabled: Whether voice output is enabled
    """
    backend: TTSBackend | None = None
    voice: str = "af_sky"
    speed: float = 1.0
    enabled: bool = True


# Backend detection cache
_backend_cache: TTSBackend | None = None


def detect_backend() -> TTSBackend:
    """Auto-detect available TTS backend.
    
    Priority order:
        1. voicemode (if installed)
        2. say (macOS built-in)
        3. silent (fallback)
    
    Returns:
        The best available TTS backend.
    """
    global _backend_cache
    
    if _backend_cache is not None:
        return _backend_cache
    
    # Check for voicemode
    if shutil.which("voicemode") is not None:
        _backend_cache = TTSBackend.VOICEMODE
        return _backend_cache
    
    # Check for macOS say
    if shutil.which("say") is not None:
        _backend_cache = TTSBackend.SAY
        return _backend_cache
    
    # Fallback to silent mode
    _backend_cache = TTSBackend.SILENT
    return _backend_cache


def reset_backend_cache() -> None:
    """Reset the backend detection cache.
    
    Useful for testing or when the environment changes.
    """
    global _backend_cache
    _backend_cache = None


async def speak(message: str, config: VoiceConfig | None = None) -> None:
    """Speak a message using the configured TTS backend.
    
    This is the main entry point for voice output. It will never raise
    an exception - any errors are logged to stderr and silently ignored.
    
    Args:
        message: The text to speak.
        config: Voice configuration. Uses defaults if not provided.
    """
    cfg = config or VoiceConfig()
    
    if not cfg.enabled:
        return
    
    if not message or not message.strip():
        return
    
    # Determine which backend to use
    backend = cfg.backend or detect_backend()
    
    try:
        if backend == TTSBackend.VOICEMODE:
            await _speak_voicemode(message, cfg.voice, cfg.speed)
        elif backend == TTSBackend.SAY:
            await _speak_macos_say(message, cfg.voice)
        else:
            await _speak_silent(message)
    except Exception as e:
        # Never crash due to TTS issues - log and continue
        print(f"[voice] TTS error ({backend.name}): {e}", file=sys.stderr)


async def _speak_voicemode(message: str, voice: str, speed: float) -> None:
    """Speak using voicemode CLI.
    
    Args:
        message: Text to speak.
        voice: Voice identifier (e.g., "af_sky", "af_bella").
        speed: Speech rate multiplier.
    
    Raises:
        RuntimeError: If voicemode command fails.
    """
    # Escape message for shell safety (basic escaping)
    safe_message = message.replace('"', '\\"')
    
    cmd = [
        "voicemode",
        "converse",
        "-m", safe_message,
        "--voice", voice,
        "--speed", str(speed),
        "--no-wait"
    ]
    
    proc = await asyncio.create_subprocess_exec(
        *cmd,
        stdout=asyncio.subprocess.DEVNULL,
        stderr=asyncio.subprocess.PIPE
    )
    
    _, stderr = await proc.communicate()
    
    if proc.returncode != 0:
        error_msg = stderr.decode('utf-8', errors='replace').strip() if stderr else "Unknown error"
        raise RuntimeError(f"voicemode failed (exit {proc.returncode}): {error_msg}")


async def _speak_macos_say(message: str, voice: str) -> None:
    """Speak using macOS built-in say command.
    
    Args:
        message: Text to speak.
        voice: Voice name (e.g., "Samantha", "Alex").
    
    Raises:
        RuntimeError: If say command fails.
    """
    cmd = ["say", "-v", voice, message]
    
    proc = await asyncio.create_subprocess_exec(
        *cmd,
        stdout=asyncio.subprocess.DEVNULL,
        stderr=asyncio.subprocess.PIPE
    )
    
    _, stderr = await proc.communicate()
    
    if proc.returncode != 0:
        error_msg = stderr.decode('utf-8', errors='replace').strip() if stderr else "Unknown error"
        raise RuntimeError(f"say failed (exit {proc.returncode}): {error_msg}")


async def _speak_silent(message: str) -> None:
    """Silent fallback - logs to stderr without producing audio.
    
    This is used when no TTS backend is available. It logs the message
    to stderr so the user knows what would have been spoken.
    
    Args:
        message: Text that would have been spoken.
    """
    print(f"[voice] {message}", file=sys.stderr)


def get_backend_info() -> dict:
    """Get information about available TTS backends.
    
    Returns:
        Dictionary with backend availability info.
    """
    return {
        "voicemode": {
            "available": shutil.which("voicemode") is not None,
            "detected": detect_backend() == TTSBackend.VOICEMODE,
        },
        "say": {
            "available": shutil.which("say") is not None,
            "detected": detect_backend() == TTSBackend.SAY,
        },
        "silent": {
            "available": True,
            "detected": detect_backend() == TTSBackend.SILENT,
        },
        "selected": detect_backend().name.lower(),
    }


# Convenience functions for testing

async def test_all_backends(message: str = "Testing voice output") -> dict[str, bool]:
    """Test all available TTS backends.
    
    Args:
        message: Test message to speak.
    
    Returns:
        Dictionary mapping backend names to success status.
    """
    results: dict[str, bool] = {}
    
    # Test voicemode if available
    if shutil.which("voicemode") is not None:
        try:
            await _speak_voicemode(message, "af_sky", 1.0)
            results["voicemode"] = True
        except Exception as e:
            print(f"[voice] voicemode test failed: {e}", file=sys.stderr)
            results["voicemode"] = False
    else:
        results["voicemode"] = False
    
    # Test say if available
    if shutil.which("say") is not None:
        try:
            await _speak_macos_say(message, "Samantha")
            results["say"] = True
        except Exception as e:
            print(f"[voice] say test failed: {e}", file=sys.stderr)
            results["say"] = False
    else:
        results["say"] = False
    
    # Silent always "works"
    results["silent"] = True
    
    return results


if __name__ == "__main__":
    # Simple CLI for testing
    import argparse
    
    parser = argparse.ArgumentParser(description="Test voice output")
    parser.add_argument("message", nargs="?", default="Voice output is working", help="Message to speak")
    parser.add_argument("--backend", choices=["voicemode", "say", "silent"], help="Force specific backend")
    parser.add_argument("--voice", default="af_sky", help="Voice to use")
    parser.add_argument("--speed", type=float, default=1.0, help="Speech speed")
    parser.add_argument("--info", action="store_true", help="Show backend info and exit")
    parser.add_argument("--test-all", action="store_true", help="Test all available backends")
    
    args = parser.parse_args()
    
    if args.info:
        import json
        print(json.dumps(get_backend_info(), indent=2))
        sys.exit(0)
    
    if args.test_all:
        results = asyncio.run(test_all_backends(args.message))
        print("Test results:")
        for backend, success in results.items():
            status = "✓" if success else "✗"
            print(f"  {status} {backend}")
        sys.exit(0 if any(results.values()) else 1)
    
    # Determine backend
    backend = None
    if args.backend:
        backend = TTSBackend[args.backend.upper()]
    
    config = VoiceConfig(backend=backend, voice=args.voice, speed=args.speed)
    
    print(f"Speaking: '{args.message}'")
    print(f"Backend: {backend.name.lower() if backend else detect_backend().name.lower()}")
    
    asyncio.run(speak(args.message, config))
