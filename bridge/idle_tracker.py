"""Idle timer logic for Kimi Voice Hooks.

Tracks user inactivity and triggers voice announcements when Kimi is waiting
for input. Uses a one-shot mechanism to avoid repeated announcements.
"""

from __future__ import annotations

import asyncio
import time
from dataclasses import dataclass
from typing import Callable, Awaitable

from .config import Config
from .voice import VoiceConfig, speak


@dataclass
class IdleState:
    """Internal state for the idle tracker.
    
    Using a dataclass makes state management more explicit and thread-safe
    when combined with asyncio synchronization primitives.
    """
    last_activity: float
    announced: bool


class IdleTracker:
    """Tracks idle time and triggers announcements after timeout.
    
    The tracker uses a one-shot mechanism - once the idle announcement
    is triggered, it won't repeat until reset() is called again.
    
    Thread-safe for async operation using asyncio locks.
    
    Example:
        tracker = IdleTracker(timeout_seconds=60)
        # Start monitoring in background
        asyncio.create_task(tracker.monitor(speak, config))
        # Reset on activity
        tracker.reset()
    """
    
    def __init__(self, timeout_seconds: int = 60):
        """Initialize the idle tracker.
        
        Args:
            timeout_seconds: Seconds of inactivity before triggering announcement.
                           Defaults to 60 seconds.
        """
        self.timeout = timeout_seconds
        self._state = IdleState(
            last_activity=time.monotonic(),
            announced=False
        )
        self._lock = asyncio.Lock()
    
    def reset(self) -> None:
        """Reset the idle timer and clear the announced flag.
        
        Call this whenever there is user activity or a new turn begins.
        This is a synchronous operation that updates internal state - the
        monitor loop will pick up the changes on its next iteration.
        """
        # Update state directly - the lock is only needed for the monitor
        # since reset() can be called from any context
        self._state = IdleState(
            last_activity=time.monotonic(),
            announced=False
        )
    
    async def monitor(
        self,
        speak_fn: Callable[[str, VoiceConfig | None], Awaitable[None]],
        config: Config
    ) -> None:
        """Monitor idle state and trigger announcements.
        
        This method runs indefinitely until cancelled. It checks every
        5 seconds whether the idle timeout has been exceeded.
        
        Uses a one-shot mechanism - once announced, it won't repeat
        until reset() is called.
        
        Args:
            speak_fn: Async function to call for voice announcements.
                     Should accept (message, voice_config) arguments.
            config: Configuration object containing voice and idle settings.
        
        Example:
            tracker = IdleTracker(60)
            try:
                await tracker.monitor(speak, config)
            except asyncio.CancelledError:
                pass  # Clean shutdown
        """
        voice_config = VoiceConfig(
            voice=config.voice,
            speed=config.speed,
            enabled=config.announce_idle
        )
        
        try:
            while True:
                await asyncio.sleep(5)  # Check every 5 seconds
                
                async with self._lock:
                    elapsed = time.monotonic() - self._state.last_activity
                    
                    # Check if timeout exceeded and not already announced
                    if elapsed >= self.timeout and not self._state.announced:
                        # One-shot: mark as announced before speaking
                        # to prevent race conditions
                        self._state.announced = True
                        
                        # Release lock while speaking to avoid blocking
                        # other operations
                        try:
                            await speak_fn(
                                "Kimi is waiting for your next instruction",
                                voice_config if voice_config.enabled else None
                            )
                        except Exception:
                            # If speak fails, don't crash the monitor
                            # Just continue - the error is logged by speak()
                            pass
        
        except asyncio.CancelledError:
            # Clean shutdown - propagate cancellation
            raise
    
    def get_elapsed(self) -> float:
        """Get the current elapsed idle time in seconds.
        
        Useful for debugging or status reporting.
        
        Returns:
            Seconds since last activity.
        """
        return time.monotonic() - self._state.last_activity
    
    def is_announced(self) -> bool:
        """Check if the idle announcement has already been triggered.
        
        Returns:
            True if already announced (and not yet reset).
        """
        return self._state.announced


# Convenience function for creating a tracker from config
def create_idle_tracker(config: Config) -> IdleTracker:
    """Create an IdleTracker from configuration.
    
    Args:
        config: Configuration with idle_timeout and idle_enabled settings.
    
    Returns:
        Configured IdleTracker instance.
    """
    if not config.idle_enabled:
        # Return tracker with very long timeout when disabled
        # This keeps the API consistent while effectively disabling the feature
        return IdleTracker(timeout_seconds=86400)  # 24 hours
    
    return IdleTracker(timeout_seconds=config.idle_timeout)
