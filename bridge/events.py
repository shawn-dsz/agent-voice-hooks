"""Event handlers for Wire protocol events.

This module handles all Wire protocol events from Kimi's --wire mode,
tracking state and triggering appropriate voice announcements.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Any

from .config import Config
from .voice import VoiceConfig, speak


@dataclass
class EventState:
    """Maintains accumulated state across events in a turn.
    
    This tracks content parts, tool calls, and other context needed
    for generating meaningful voice announcements.
    """
    accumulated_content: list[str] = field(default_factory=list)
    tool_calls: list[dict[str, Any]] = field(default_factory=list)
    current_turn: int = 0
    
    def reset(self) -> None:
        """Clear all accumulated state (called on TurnBegin)."""
        self.accumulated_content.clear()
        self.tool_calls.clear()
    
    def add_content(self, content: str) -> None:
        """Add text content to accumulation."""
        if content and content.strip():
            self.accumulated_content.append(content)
    
    def add_tool_call(self, tool_call: dict[str, Any]) -> None:
        """Track a tool call for context."""
        self.tool_calls.append(tool_call)


class EventHandler:
    """Handler for Wire protocol events.
    
    Maintains state across events in a turn and triggers voice announcements
    at appropriate moments (turn end, approval requests, etc.).
    
    Example:
        handler = EventHandler()
        await handler.on_turn_begin()
        await handler.on_content_part("Hello world")
        await handler.on_turn_end(config)
    """
    
    def __init__(self):
        """Initialize the event handler with empty state."""
        self._state = EventState()
    
    async def on_turn_begin(self, idle_tracker: Any | None = None) -> None:
        """Handle TurnBegin event.
        
        Resets accumulated content state and the idle timer.
        No voice announcement is made for this event.
        
        Args:
            idle_tracker: Optional IdleTracker to reset on turn start.
        """
        self._state.reset()
        self._state.current_turn += 1
        
        # Reset idle timer if provided
        if idle_tracker is not None:
            idle_tracker.reset()
    
    async def on_turn_end(
        self,
        config: Config,
        idle_tracker: Any | None = None
    ) -> str:
        """Handle TurnEnd event.
        
        Announces a brief summary of the completed task (~10 words).
        Resets the idle timer since the user now needs to respond.
        
        Args:
            config: Configuration with voice and announcement settings.
            idle_tracker: Optional IdleTracker to reset after turn completion.
        
        Returns:
            The announcement message that was spoken (or would have been).
        """
        # Reset idle timer since turn is done
        if idle_tracker is not None:
            idle_tracker.reset()
        
        if not config.announce_turn_end:
            return ""
        
        voice_config = VoiceConfig(
            voice=config.voice,
            speed=config.speed,
            enabled=True
        )
        
        # Generate summary from accumulated content
        if not self._state.accumulated_content:
            message = "Task completed. Ready for next instructions."
        else:
            # Take the last content block for the summary
            last_content = self._state.accumulated_content[-1]
            summary = self._truncate_to_words(last_content, max_words=10)
            message = f"Done: {summary}"
        
        await speak(message, voice_config)
        return message
    
    async def on_content_part(self, content: dict[str, Any] | str) -> None:
        """Handle ContentPart event.
        
        Accumulates text content for use in turn-end summaries.
        No voice announcement is made for this event.
        
        Args:
            content: Content part data, either as a dict with 'text' or 'content'
                    field, or as a raw string.
        """
        text = self._extract_text(content)
        if text:
            self._state.add_content(text)
    
    async def on_approval_request(
        self,
        payload: dict[str, Any],
        config: Config
    ) -> str:
        """Handle ApprovalRequest event.
        
        Announces the permission request and returns a cleaned-up
        description suitable for terminal display.
        
        Args:
            payload: The ApprovalRequest payload containing action, sender, etc.
            config: Configuration with voice and announcement settings.
        
        Returns:
            The announcement message that was spoken (or would have been).
        """
        if not config.announce_approval:
            return ""
        
        voice_config = VoiceConfig(
            voice=config.voice,
            speed=config.speed,
            enabled=True
        )
        
        # Extract and clean up the action
        action = payload.get("action", "")
        sender = payload.get("sender", "")
        
        if action:
            # Clean up common shell command prefixes
            clean_action = self._clean_action(action)
            message = f"Waiting for permission to {clean_action}"
        elif sender:
            message = f"Waiting for permission from {sender}"
        else:
            message = "Waiting for your permission"
        
        await speak(message, voice_config)
        return message
    
    async def on_step_interrupted(self, config: Config) -> str | None:
        """Handle StepInterrupted event.
        
        Announces if the interruption is unexpected (based on config).
        
        Args:
            config: Configuration with announcement settings.
        
        Returns:
            The announcement message if one was made, None otherwise.
        """
        if not config.announce_errors:
            return None
        
        voice_config = VoiceConfig(
            voice=config.voice,
            speed=config.speed,
            enabled=True
        )
        
        message = "Task was interrupted"
        await speak(message, voice_config)
        return message
    
    async def on_tool_call(self, tool_call: dict[str, Any]) -> None:
        """Handle ToolCall event.
        
        Tracks tool calls for context (e.g., which files were edited).
        No voice announcement is made for this event.
        
        Args:
            tool_call: The tool call data containing name, arguments, etc.
        """
        self._state.add_tool_call(tool_call)
    
    def get_accumulated_content(self) -> list[str]:
        """Get the currently accumulated content parts.
        
        Returns:
            List of accumulated content strings.
        """
        return list(self._state.accumulated_content)
    
    def get_tool_calls(self) -> list[dict[str, Any]]:
        """Get the tracked tool calls.
        
        Returns:
            List of tool call dictionaries.
        """
        return list(self._state.tool_calls)
    
    @staticmethod
    def _extract_text(content: dict[str, Any] | str) -> str | None:
        """Extract text from a content part.
        
        Handles various content formats:
        - String (direct text)
        - Dict with 'text' key
        - Dict with 'content' key
        - Dict with 'body' key
        
        Args:
            content: Content part in various formats.
        
        Returns:
            Extracted text or None if no text found.
        """
        if isinstance(content, str):
            return content if content.strip() else None
        
        if isinstance(content, dict):
            # Try common text fields
            for key in ("text", "content", "body", "value", "message"):
                if key in content and isinstance(content[key], str):
                    text = content[key].strip()
                    if text:
                        return text
        
        return None
    
    @staticmethod
    def _truncate_to_words(text: str, max_words: int = 10) -> str:
        """Truncate text to approximately max_words words.
        
        Args:
            text: Text to truncate.
            max_words: Maximum number of words to include.
        
        Returns:
            Truncated text with "..." appended if truncated.
        """
        # Normalize whitespace and split
        words = text.split()
        
        if len(words) <= max_words:
            return text
        
        truncated = " ".join(words[:max_words])
        return truncated + "..."
    
    @staticmethod
    def _clean_action(action: str) -> str:
        """Clean up shell command prefixes from approval actions.
        
        Removes common prefixes like "run shell command:" or "execute:"
        to make the announcement more natural.
        
        Args:
            action: Raw action string from ApprovalRequest.
        
        Returns:
            Cleaned action string suitable for voice announcement.
        """
        # Remove common prefixes (case-insensitive)
        patterns = [
            r"^(run shell command|execute|exec|shell|bash|sh|zsh)\s*[:\-]?\s*",
            r"^(run|execute|perform)\s+(command|script|action)\s*[:\-]?\s*",
        ]
        
        cleaned = action
        for pattern in patterns:
            cleaned = re.sub(pattern, "", cleaned, flags=re.IGNORECASE)
        
        return cleaned.strip()


# Convenience functions for direct event handling
# These allow simpler usage patterns for one-off events

async def handle_turn_end(
    accumulated_content: list[str],
    config: Config
) -> str:
    """Standalone handler for TurnEnd events.
    
    Args:
        accumulated_content: List of accumulated content strings.
        config: Configuration with voice and announcement settings.
    
    Returns:
        The announcement message.
    """
    handler = EventHandler()
    for content in accumulated_content:
        await handler.on_content_part(content)
    return await handler.on_turn_end(config)


async def handle_approval_request(
    payload: dict[str, Any],
    config: Config
) -> str:
    """Standalone handler for ApprovalRequest events.
    
    Args:
        payload: The ApprovalRequest payload.
        config: Configuration with voice and announcement settings.
    
    Returns:
        The announcement message.
    """
    handler = EventHandler()
    return await handler.on_approval_request(payload, config)
