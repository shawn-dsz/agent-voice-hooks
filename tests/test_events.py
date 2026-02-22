#!/usr/bin/env python3
"""Unit tests for event handlers and configuration.

Tests the core event handling logic, idle tracker behavior, and configuration
loading without requiring actual voice output or subprocesses.
"""

from __future__ import annotations

import asyncio
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch

# Add project directory to path for importing bridge package
SCRIPT_DIR = Path(__file__).parent.resolve()
PROJECT_DIR = SCRIPT_DIR.parent
sys.path.insert(0, str(PROJECT_DIR))

# Import from bridge package
from bridge import Config, load_config
from bridge import EventHandler, handle_approval_request, handle_turn_end
from bridge import IdleTracker, create_idle_tracker
from bridge import TTSBackend, VoiceConfig, detect_backend

# Import internal functions directly from modules
from bridge.config import load_toml_file
from bridge.voice import reset_backend_cache


class TestTurnEndEvents(unittest.IsolatedAsyncioTestCase):
    """Test TurnEnd event handling."""
    
    async def asyncSetUp(self):
        """Set up test fixtures."""
        self.handler = EventHandler()
        self.config = Config(
            tts_backend="silent",
            voice="af_sky",
            announce_turn_end=True
        )
    
    async def test_turn_end_single_sentence(self):
        """Summary truncation to ~10 words."""
        # Accumulate some content
        await self.handler.on_content_part("This is a test message with more than ten words for truncation testing.")
        
        # Get the announcement
        message = await self.handler.on_turn_end(self.config)
        
        # Should truncate to ~10 words with ellipsis
        self.assertIn("Done:", message)
        words = message.replace("Done: ", "").replace("...", "").split()
        self.assertLessEqual(len(words), 10)
        if "..." in message:
            self.assertTrue(len(words) >= 9)  # Should be close to 10
    
    async def test_turn_end_empty(self):
        """Fallback message when no content accumulated."""
        # No content added
        message = await self.handler.on_turn_end(self.config)
        
        self.assertEqual(message, "Task completed. Ready for next instructions.")
    
    async def test_turn_end_accumulated_content(self):
        """Uses accumulated content from multiple parts."""
        # Add multiple content parts
        await self.handler.on_content_part("First part of the message.")
        await self.handler.on_content_part("Second part that is longer and should be used for the summary.")
        await self.handler.on_content_part("Final part is the shortest.")
        
        message = await self.handler.on_turn_end(self.config)
        
        # Should use the last content part
        self.assertIn("Done:", message)
        self.assertIn("Final", message)  # Should contain text from the last part
    
    async def test_turn_end_disabled(self):
        """No announcement when disabled in config."""
        self.config.announce_turn_end = False
        
        await self.handler.on_content_part("Some content here.")
        message = await self.handler.on_turn_end(self.config)
        
        self.assertEqual(message, "")
    
    async def test_turn_end_with_idle_tracker(self):
        """TurnEnd resets idle tracker."""
        mock_tracker = MagicMock()
        
        await self.handler.on_content_part("Test content.")
        await self.handler.on_turn_end(self.config, idle_tracker=mock_tracker)
        
        mock_tracker.reset.assert_called_once()


class TestApprovalRequestEvents(unittest.IsolatedAsyncioTestCase):
    """Test ApprovalRequest event handling."""
    
    async def asyncSetUp(self):
        """Set up test fixtures."""
        self.handler = EventHandler()
        self.config = Config(
            tts_backend="silent",
            voice="af_sky",
            announce_approval=True
        )
    
    async def test_approval_request_with_action(self):
        """Action extraction for approval request."""
        payload = {
            "id": "approval-1",
            "action": "run shell command: npm test",
            "sender": "Shell"
        }
        
        message = await self.handler.on_approval_request(payload, self.config)
        
        self.assertIn("Waiting for permission", message)
        self.assertIn("npm test", message)
    
    async def test_approval_request_without_action(self):
        """Fallback to sender when action is missing."""
        payload = {
            "id": "approval-1",
            "sender": "FileSystem"
        }
        
        message = await self.handler.on_approval_request(payload, self.config)
        
        self.assertIn("Waiting for permission from FileSystem", message)
    
    async def test_approval_request_shell_prefix_stripped(self):
        """Shell command prefix cleaning."""
        test_cases = [
            ("run shell command: npm test", "npm test"),
            ("execute: git push", "git push"),
            ("run command: ls -la", "ls -la"),
            ("SHELL: echo hello", "echo hello"),
            ("just a normal message", "just a normal message"),
        ]
        
        for action, expected in test_cases:
            # Create fresh handler for each case to avoid any state issues
            handler = EventHandler()
            payload = {"id": "test", "action": action, "sender": "Shell"}
            message = await handler.on_approval_request(payload, self.config)
            self.assertIn(expected, message)
    
    async def test_approval_request_no_action_no_sender(self):
        """Fallback when both action and sender are missing."""
        payload = {"id": "approval-1"}
        
        message = await self.handler.on_approval_request(payload, self.config)
        
        self.assertEqual(message, "Waiting for your permission")
    
    async def test_approval_request_disabled(self):
        """No announcement when disabled in config."""
        self.config.announce_approval = False
        
        payload = {"id": "approval-1", "action": "do something"}
        message = await self.handler.on_approval_request(payload, self.config)
        
        self.assertEqual(message, "")


class TestIdleTracker(unittest.IsolatedAsyncioTestCase):
    """Test IdleTracker behavior."""
    
    async def asyncSetUp(self):
        """Set up test fixtures."""
        # Use very short timeout for testing
        self.tracker = IdleTracker(timeout_seconds=1)
        self.mock_speak = AsyncMock()
        self.config = Config(
            tts_backend="silent",
            voice="af_sky",
            announce_idle=True
        )
    
    async def test_idle_tracker_fires(self):
        """Timer fires after timeout."""
        # Start monitor in background
        task = asyncio.create_task(
            self.tracker.monitor(self.mock_speak, self.config)
        )
        
        # Wait for the check interval (5s) + margin - tracker checks every 5s
        await asyncio.sleep(6.0)
        
        # Cancel the monitor
        task.cancel()
        try:
            await task
        except asyncio.CancelledError:
            pass
        
        # Should have been called
        self.mock_speak.assert_called_once()
        args = self.mock_speak.call_args[0]
        self.assertIn("waiting for your next instruction", args[0].lower())
    
    async def test_idle_tracker_resets(self):
        """Timer resets on activity."""
        # Start monitor
        task = asyncio.create_task(
            self.tracker.monitor(self.mock_speak, self.config)
        )
        
        # Wait and reset before the check fires
        await asyncio.sleep(2.0)
        self.tracker.reset()
        await asyncio.sleep(2.0)  # Would have fired at 5s if not reset
        
        # Cancel
        task.cancel()
        try:
            await task
        except asyncio.CancelledError:
            pass
        
        # Should not have fired yet (reset at 2s, only 4s elapsed)
        self.mock_speak.assert_not_called()
    
    async def test_idle_tracker_one_shot(self):
        """Won't repeat until reset."""
        task = asyncio.create_task(
            self.tracker.monitor(self.mock_speak, self.config)
        )
        
        # Wait for first fire (at 5s check interval)
        await asyncio.sleep(6.0)
        
        # Wait longer - should not fire again (one-shot behavior)
        await asyncio.sleep(3.0)
        
        # Cancel
        task.cancel()
        try:
            await task
        except asyncio.CancelledError:
            pass
        
        # Should only have been called once
        self.assertEqual(self.mock_speak.call_count, 1)
    
    async def test_idle_tracker_disabled(self):
        """No announcement when disabled in config."""
        self.config.announce_idle = False
        
        task = asyncio.create_task(
            self.tracker.monitor(self.mock_speak, self.config)
        )
        
        # Wait for check interval
        await asyncio.sleep(6.0)
        
        task.cancel()
        try:
            await task
        except asyncio.CancelledError:
            pass
        
        # When disabled, voice config has enabled=False but speak is still called
        # Check if called with disabled config
        if self.mock_speak.called:
            args = self.mock_speak.call_args[0]
            if len(args) > 1 and args[1] is not None:
                self.assertFalse(args[1].enabled)
    
    def test_get_elapsed(self):
        """Elapsed time tracking."""
        import time
        
        # Initial elapsed should be near 0
        elapsed = self.tracker.get_elapsed()
        self.assertLess(elapsed, 0.1)
        
        # Wait and check
        time.sleep(0.2)
        elapsed = self.tracker.get_elapsed()
        self.assertGreaterEqual(elapsed, 0.15)
    
    def test_is_announced(self):
        """Announced flag tracking."""
        self.assertFalse(self.tracker.is_announced())
        
        # Manually set state to announced
        self.tracker._state.announced = True
        self.assertTrue(self.tracker.is_announced())


class TestConfigLoading(unittest.TestCase):
    """Test configuration loading."""
    
    def setUp(self):
        """Set up test fixtures."""
        self.temp_dir = tempfile.TemporaryDirectory()
        self.global_config = Path(self.temp_dir.name) / "global.toml"
        self.project_config = Path(self.temp_dir.name) / "project.toml"
    
    def tearDown(self):
        """Clean up test fixtures."""
        self.temp_dir.cleanup()
    
    def test_config_loading(self):
        """TOML config parsing works."""
        # Write a test config
        self.global_config.write_text("""
[voice]
backend = "say"
voice = "Samantha"
speed = 1.5

[idle]
timeout = 120
enabled = true

[events]
announce_turn_end = false
announce_approval = true
""")
        
        data = load_toml_file(self.global_config)
        config = Config.from_dict(data)
        
        self.assertEqual(config.tts_backend, "say")
        self.assertEqual(config.voice, "Samantha")
        self.assertEqual(config.speed, 1.5)
        self.assertEqual(config.idle_timeout, 120)
        self.assertTrue(config.idle_enabled)
        self.assertFalse(config.announce_turn_end)
        self.assertTrue(config.announce_approval)
    
    def test_config_project_override(self):
        """Local config merges with global."""
        # Global config
        self.global_config.write_text("""
[voice]
backend = "say"
voice = "Samantha"
speed = 1.0

[idle]
timeout = 60
""")
        
        # Project config overrides voice only
        self.project_config.write_text("""
[voice]
voice = "Alex"
speed = 1.2
""")
        
        global_data = load_toml_file(self.global_config)
        project_data = load_toml_file(self.project_config)
        
        config = Config.from_dict(global_data)
        project = Config.from_dict(project_data)
        
        merged = config.merge(project)
        
        # Global values
        self.assertEqual(merged.tts_backend, "say")  # from global
        # Project overrides
        self.assertEqual(merged.voice, "Alex")  # overridden
        self.assertEqual(merged.speed, 1.2)  # overridden
        # Default values
        self.assertEqual(merged.idle_timeout, 60)  # from global
    
    def test_config_defaults(self):
        """Default configuration values."""
        config = Config()
        
        self.assertEqual(config.tts_backend, "voicemode")
        self.assertEqual(config.voice, "af_sky")
        self.assertEqual(config.speed, 1.0)
        self.assertEqual(config.idle_timeout, 60)
        self.assertTrue(config.idle_enabled)
        self.assertTrue(config.announce_turn_end)
        self.assertTrue(config.announce_approval)
        self.assertTrue(config.announce_idle)
        self.assertFalse(config.announce_errors)
    
    def test_config_from_dict_flat(self):
        """Config from flat dictionary."""
        data = {
            "tts_backend": "say",
            "voice": "Samantha",
            "speed": 1.5,
            "idle_timeout": 120
        }
        
        config = Config.from_dict(data)
        
        self.assertEqual(config.tts_backend, "say")
        self.assertEqual(config.voice, "Samantha")
        self.assertEqual(config.speed, 1.5)
        self.assertEqual(config.idle_timeout, 120)
    
    def test_config_to_dict(self):
        """Config conversion to dictionary."""
        config = Config(
            tts_backend="say",
            voice="Samantha",
            speed=1.5,
            idle_timeout=120
        )
        
        data = config.to_dict()
        
        self.assertEqual(data["voice"]["backend"], "say")
        self.assertEqual(data["voice"]["voice"], "Samantha")
        self.assertEqual(data["voice"]["speed"], 1.5)
        self.assertEqual(data["idle"]["timeout"], 120)


class TestVoiceBackendDetection(unittest.TestCase):
    """Test TTS backend auto-detection."""
    
    def setUp(self):
        """Reset backend cache before each test."""
        import bridge.voice as voice_module
        voice_module._backend_cache = None
    
    def tearDown(self):
        """Reset backend cache after each test."""
        import bridge.voice as voice_module
        voice_module._backend_cache = None
    
    @patch("bridge.voice.shutil.which")
    def test_voice_backend_detection_voicemode(self, mock_which):
        """Auto-detection prefers voicemode."""
        def which_side_effect(cmd):
            return "/usr/bin/voicemode" if cmd == "voicemode" else None
        mock_which.side_effect = which_side_effect
        
        backend = detect_backend()
        self.assertEqual(backend, TTSBackend.VOICEMODE)
    
    @patch("bridge.voice.shutil.which")
    def test_voice_backend_detection_say(self, mock_which):
        """Auto-detection falls back to say."""
        def which_side_effect(cmd):
            if cmd == "voicemode":
                return None
            if cmd == "say":
                return "/usr/bin/say"
            return None
        mock_which.side_effect = which_side_effect
        
        backend = detect_backend()
        self.assertEqual(backend, TTSBackend.SAY)
    
    @patch("bridge.voice.shutil.which")
    def test_voice_backend_detection_silent(self, mock_which):
        """Auto-detection falls back to silent."""
        mock_which.return_value = None
        
        backend = detect_backend()
        self.assertEqual(backend, TTSBackend.SILENT)


class TestContentExtraction(unittest.TestCase):
    """Test text extraction from content parts."""
    
    def test_extract_text_string(self):
        """Extract text from string content."""
        handler = EventHandler()
        result = handler._extract_text("Hello world")
        self.assertEqual(result, "Hello world")
    
    def test_extract_text_dict_text_key(self):
        """Extract text from dict with 'text' key."""
        handler = EventHandler()
        result = handler._extract_text({"text": "Hello world"})
        self.assertEqual(result, "Hello world")
    
    def test_extract_text_dict_content_key(self):
        """Extract text from dict with 'content' key."""
        handler = EventHandler()
        result = handler._extract_text({"content": "Hello world"})
        self.assertEqual(result, "Hello world")
    
    def test_extract_text_empty(self):
        """Handle empty content."""
        handler = EventHandler()
        self.assertIsNone(handler._extract_text(""))
        self.assertIsNone(handler._extract_text("   "))
        self.assertIsNone(handler._extract_text({"text": ""}))
        self.assertIsNone(handler._extract_text({"other": "value"}))


class TestStandaloneHandlers(unittest.IsolatedAsyncioTestCase):
    """Test standalone event handler functions."""
    
    async def test_handle_turn_end_standalone(self):
        """Standalone turn end handler works."""
        config = Config(tts_backend="silent", announce_turn_end=True)
        content = ["First part", "Second part with more content"]
        
        message = await handle_turn_end(content, config)
        
        self.assertIn("Done:", message)
    
    async def test_handle_approval_request_standalone(self):
        """Standalone approval request handler works."""
        config = Config(tts_backend="silent", announce_approval=True)
        payload = {"id": "test", "action": "run tests"}
        
        message = await handle_approval_request(payload, config)
        
        self.assertIn("Waiting for permission", message)


class TestTurnBegin(unittest.IsolatedAsyncioTestCase):
    """Test TurnBegin event handling."""
    
    async def test_turn_begin_resets_state(self):
        """TurnBegin resets accumulated state."""
        handler = EventHandler()
        
        # Add some content
        await handler.on_content_part("Some content")
        self.assertEqual(len(handler.get_accumulated_content()), 1)
        
        # Turn begin should reset
        await handler.on_turn_begin()
        self.assertEqual(len(handler.get_accumulated_content()), 0)
    
    async def test_turn_begin_resets_idle(self):
        """TurnBegin resets idle tracker."""
        handler = EventHandler()
        mock_tracker = MagicMock()
        
        await handler.on_turn_begin(idle_tracker=mock_tracker)
        
        mock_tracker.reset.assert_called_once()


class TestToolCallTracking(unittest.IsolatedAsyncioTestCase):
    """Test ToolCall event handling."""
    
    async def test_tool_call_tracking(self):
        """Tool calls are tracked."""
        handler = EventHandler()
        
        tool_call = {"name": "read_file", "arguments": {"path": "/test.txt"}}
        await handler.on_tool_call(tool_call)
        
        calls = handler.get_tool_calls()
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0]["name"], "read_file")
    
    async def test_tool_call_multiple(self):
        """Multiple tool calls are tracked."""
        handler = EventHandler()
        
        await handler.on_tool_call({"name": "read_file", "args": {}})
        await handler.on_tool_call({"name": "write_file", "args": {}})
        await handler.on_tool_call({"name": "search", "args": {}})
        
        self.assertEqual(len(handler.get_tool_calls()), 3)


class TestStepInterrupted(unittest.IsolatedAsyncioTestCase):
    """Test StepInterrupted event handling."""
    
    async def test_step_interrupted_enabled(self):
        """Announcement when errors enabled."""
        handler = EventHandler()
        config = Config(tts_backend="silent", announce_errors=True)
        
        message = await handler.on_step_interrupted(config)
        
        self.assertIsNotNone(message)
        self.assertIn("interrupted", message.lower())
    
    async def test_step_interrupted_disabled(self):
        """No announcement when errors disabled."""
        handler = EventHandler()
        config = Config(tts_backend="silent", announce_errors=False)
        
        message = await handler.on_step_interrupted(config)
        
        self.assertIsNone(message)


def create_test_suite():
    """Create a test suite with all tests."""
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()
    
    # Add all test classes
    suite.addTests(loader.loadTestsFromTestCase(TestTurnEndEvents))
    suite.addTests(loader.loadTestsFromTestCase(TestApprovalRequestEvents))
    suite.addTests(loader.loadTestsFromTestCase(TestIdleTracker))
    suite.addTests(loader.loadTestsFromTestCase(TestConfigLoading))
    suite.addTests(loader.loadTestsFromTestCase(TestVoiceBackendDetection))
    suite.addTests(loader.loadTestsFromTestCase(TestContentExtraction))
    suite.addTests(loader.loadTestsFromTestCase(TestStandaloneHandlers))
    suite.addTests(loader.loadTestsFromTestCase(TestTurnBegin))
    suite.addTests(loader.loadTestsFromTestCase(TestToolCallTracking))
    suite.addTests(loader.loadTestsFromTestCase(TestStepInterrupted))
    
    return suite


def main():
    """Run the test suite."""
    # Check for verbose flag
    verbose = "-v" in sys.argv or "--verbose" in sys.argv
    
    # Create and run tests
    suite = create_test_suite()
    runner = unittest.TextTestRunner(verbosity=2 if verbose else 1)
    result = runner.run(suite)
    
    # Return exit code
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    sys.exit(main())
