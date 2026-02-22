#!/usr/bin/env python3
"""Main bridge for Kimi Voice Hooks.

Spawns `kimi --wire` as a subprocess and proxies communication between
the user's terminal and Kimi, intercepting Wire protocol events to trigger
voice announcements.

Architecture:
    - Three concurrent async tasks:
        1. forward_user_input: Read terminal stdin, forward to Kimi
        2. process_kimi_output: Read Kimi stdout, handle events, forward to terminal
        3. idle_monitor: Run idle tracker to detect user inactivity
"""

from __future__ import annotations

import asyncio
import json
import signal
import sys
from pathlib import Path
from typing import Any

# Import local modules
from .config import Config, load_config
from .events import EventHandler
from .idle_tracker import IdleTracker, create_idle_tracker
from .voice import VoiceConfig, speak


# Global state for graceful shutdown
_shutdown_event = asyncio.Event()


class BridgeError(Exception):
    """Base exception for bridge errors."""
    pass


class ProtocolError(BridgeError):
    """JSON-RPC protocol error."""
    pass


async def forward_user_input(
    writer: asyncio.StreamWriter,
    idle_tracker: IdleTracker
) -> None:
    """Forward user input from terminal stdin to Kimi's stdin.
    
    Reads line by line from sys.stdin and writes to the subprocess.
    Resets idle tracker on any input activity.
    
    Args:
        writer: StreamWriter connected to Kimi's stdin.
        idle_tracker: Idle tracker to reset on user input.
    """
    loop = asyncio.get_event_loop()
    
    try:
        while not _shutdown_event.is_set():
            # Read from stdin in a thread-safe way
            try:
                line = await loop.run_in_executor(None, sys.stdin.readline)
            except (KeyboardInterrupt, EOFError):
                break
            
            if not line:
                # EOF reached
                break
            
            # Reset idle timer on any user activity
            idle_tracker.reset()
            
            # Forward to Kimi
            try:
                writer.write(line.encode('utf-8'))
                await writer.drain()
            except (BrokenPipeError, ConnectionResetError):
                # Kimi process closed stdin
                break
    
    except asyncio.CancelledError:
        # Clean cancellation
        pass
    
    finally:
        # Close stdin to signal EOF to Kimi
        try:
            writer.close()
            await writer.wait_closed()
        except Exception:
            pass


async def process_kimi_output(
    reader: asyncio.StreamReader,
    event_handler: EventHandler,
    idle_tracker: IdleTracker,
    config: Config
) -> None:
    """Process output from Kimi, handling events and forwarding to terminal.
    
    Reads line-delimited JSON-RPC messages from Kimi's stdout, parses them,
    handles specific events (TurnEnd, ApprovalRequest, etc.), and forwards
    the raw JSON to the terminal stdout.
    
    Args:
        reader: StreamReader connected to Kimi's stdout.
        event_handler: Event handler for processing Wire events.
        idle_tracker: Idle tracker to reset on activity.
        config: Bridge configuration.
    """
    pending_approval: dict[str, Any] | None = None
    
    try:
        while not _shutdown_event.is_set():
            try:
                # Read line from Kimi (with timeout to allow shutdown checks)
                line = await asyncio.wait_for(
                    reader.readline(),
                    timeout=0.5
                )
            except asyncio.TimeoutError:
                continue
            
            if not line:
                # EOF - Kimi process ended
                break
            
            # Forward raw line to terminal immediately (keep Kimi output transparent)
            try:
                sys.stdout.write(line.decode('utf-8', errors='replace'))
                sys.stdout.flush()
            except Exception:
                pass
            
            # Parse and handle events
            try:
                message = json.loads(line)
                await _handle_jsonrpc_message(
                    message,
                    event_handler,
                    idle_tracker,
                    config
                )
            except json.JSONDecodeError:
                # Not JSON - just pass through (might be non-JSON output)
                pass
            except Exception as e:
                # Log error but don't crash the bridge
                print(f"[bridge] Error handling message: {e}", file=sys.stderr)
    
    except asyncio.CancelledError:
        # Clean cancellation
        pass


async def _handle_jsonrpc_message(
    message: dict[str, Any],
    event_handler: EventHandler,
    idle_tracker: IdleTracker,
    config: Config
) -> None:
    """Handle a single JSON-RPC message from Kimi.
    
    Args:
        message: Parsed JSON-RPC message.
        event_handler: Event handler for processing events.
        idle_tracker: Idle tracker to reset on activity.
        config: Bridge configuration.
    """
    # Check for JSON-RPC 2.0 format
    if message.get("jsonrpc") != "2.0":
        return
    
    method = message.get("method", "")
    params = message.get("params", {})
    
    # Handle different message types
    if method == "initialize":
        # Protocol initialization - log but don't announce
        pass
    
    elif method == "event":
        # Wire protocol event
        event_type = params.get("type", "")
        payload = params.get("payload", {})
        
        await _handle_wire_event(
            event_type,
            payload,
            event_handler,
            idle_tracker,
            config
        )
    
    elif method == "request":
        # Wire protocol request (requires response)
        request_type = params.get("type", "")
        payload = params.get("payload", {})
        request_id = message.get("id")
        
        await _handle_wire_request(
            request_type,
            payload,
            request_id,
            event_handler,
            config
        )


async def _handle_wire_event(
    event_type: str,
    payload: dict[str, Any],
    event_handler: EventHandler,
    idle_tracker: IdleTracker,
    config: Config
) -> None:
    """Handle a Wire protocol event.
    
    Args:
        event_type: Type of event (TurnBegin, TurnEnd, etc.).
        payload: Event payload data.
        event_handler: Event handler for processing events.
        idle_tracker: Idle tracker to reset on activity.
        config: Bridge configuration.
    """
    if event_type == "TurnBegin":
        await event_handler.on_turn_begin(idle_tracker)
    
    elif event_type == "TurnEnd":
        # Debounce rapid TurnEnd events
        await _debounced_turn_end(event_handler, idle_tracker, config)
    
    elif event_type == "ContentPart":
        await event_handler.on_content_part(payload)
    
    elif event_type == "ToolCall":
        await event_handler.on_tool_call(payload)
    
    elif event_type == "StepInterrupted":
        await event_handler.on_step_interrupted(config)
    
    # Other events are passed through without handling


# Debounce tracking for TurnEnd events
_last_turn_end_time: float = 0.0
_turn_end_lock = asyncio.Lock()


async def _debounced_turn_end(
    event_handler: EventHandler,
    idle_tracker: IdleTracker,
    config: Config
) -> None:
    """Handle TurnEnd with debouncing for rapid successive events.
    
    Only announces the last TurnEnd within a 2-second window.
    
    Args:
        event_handler: Event handler for processing events.
        idle_tracker: Idle tracker to reset on activity.
        config: Bridge configuration.
    """
    global _last_turn_end_time
    
    import time
    current_time = time.monotonic()
    
    async with _turn_end_lock:
        # Check if we're within the debounce window
        if current_time - _last_turn_end_time < 2.0:
            # Within debounce window - reset and return without announcing
            _last_turn_end_time = current_time
            idle_tracker.reset()
            return
        
        _last_turn_end_time = current_time
    
    # Small delay to allow for rapid successive events
    await asyncio.sleep(0.1)
    
    # Check again after delay
    async with _turn_end_lock:
        if current_time != _last_turn_end_time:
            # Another TurnEnd came in during delay, skip this one
            return
    
    # Actually process the TurnEnd
    await event_handler.on_turn_end(config, idle_tracker)


async def _handle_wire_request(
    request_type: str,
    payload: dict[str, Any],
    request_id: Any,
    event_handler: EventHandler,
    config: Config
) -> None:
    """Handle a Wire protocol request (requires JSON-RPC response).
    
    Args:
        request_type: Type of request (ApprovalRequest, etc.).
        payload: Request payload data.
        request_id: JSON-RPC request ID for the response.
        event_handler: Event handler for processing events.
        config: Bridge configuration.
    """
    if request_type == "ApprovalRequest":
        # Announce the approval request
        await event_handler.on_approval_request(payload, config)
        
        # The approval prompt is already displayed by Kimi through stdout
        # We just need to handle the response - but Kimi's term handling
        # will capture the response. The bridge just announces it.
        # No need to send a response here as Kimi handles the approval flow.


async def idle_monitor(
    idle_tracker: IdleTracker,
    config: Config
) -> None:
    """Run the idle tracker monitor.
    
    Args:
        idle_tracker: Idle tracker instance to monitor.
        config: Configuration with voice settings.
    """
    voice_config = VoiceConfig(
        voice=config.voice,
        speed=config.speed,
        enabled=True
    )
    
    try:
        await idle_tracker.monitor(speak, config)
    except asyncio.CancelledError:
        # Clean cancellation
        pass


async def forward_stderr(reader: asyncio.StreamReader) -> None:
    """Forward stderr from Kimi subprocess to terminal stderr.
    
    Args:
        reader: StreamReader connected to Kimi's stderr.
    """
    try:
        while not _shutdown_event.is_set():
            try:
                line = await asyncio.wait_for(
                    reader.readline(),
                    timeout=0.5
                )
            except asyncio.TimeoutError:
                continue
            
            if not line:
                break
            
            # Forward to terminal stderr
            try:
                sys.stderr.write(line.decode('utf-8', errors='replace'))
                sys.stderr.flush()
            except Exception:
                pass
    
    except asyncio.CancelledError:
        pass


def setup_signal_handlers() -> None:
    """Set up signal handlers for graceful shutdown."""
    def signal_handler(sig: int, frame: Any) -> None:
        _shutdown_event.set()
    
    try:
        signal.signal(signal.SIGINT, signal_handler)
        signal.signal(signal.SIGTERM, signal_handler)
    except (ValueError, OSError):
        # Signals may not be available on all platforms
        pass


async def main() -> int:
    """Main bridge entry point.
    
    Returns:
        Exit code (0 for success, non-zero for errors).
    """
    # Load configuration
    config = load_config()
    
    # Set up signal handlers
    setup_signal_handlers()
    
    # Create event handler and idle tracker
    event_handler = EventHandler()
    idle_tracker = create_idle_tracker(config)
    
    # Prepare kimi command
    kimi_cmd = config.kimi_command
    kimi_args = ["--wire"] + config.extra_args + sys.argv[1:]
    
    # Spawn kimi subprocess
    try:
        proc = await asyncio.create_subprocess_exec(
            kimi_cmd,
            *kimi_args,
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
    except FileNotFoundError:
        print(f"[bridge] Error: '{kimi_cmd}' not found. Is Kimi CLI installed?", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"[bridge] Error spawning kimi: {e}", file=sys.stderr)
        return 1
    
    # Create tasks for concurrent operation
    tasks = []
    
    # Task 1: Forward user input to Kimi
    if proc.stdin:
        stdin_task = asyncio.create_task(
            forward_user_input(proc.stdin, idle_tracker),
            name="stdin_forwarder"
        )
        tasks.append(stdin_task)
    
    # Task 2: Process Kimi output
    if proc.stdout:
        stdout_task = asyncio.create_task(
            process_kimi_output(
                proc.stdout,
                event_handler,
                idle_tracker,
                config
            ),
            name="stdout_processor"
        )
        tasks.append(stdout_task)
    
    # Task 3: Forward Kimi stderr
    if proc.stderr:
        stderr_task = asyncio.create_task(
            forward_stderr(proc.stderr),
            name="stderr_forwarder"
        )
        tasks.append(stderr_task)
    
    # Task 4: Idle monitor
    idle_task = asyncio.create_task(
        idle_monitor(idle_tracker, config),
        name="idle_monitor"
    )
    tasks.append(idle_task)
    
    # Task 5: Wait for subprocess and signal shutdown
    async def wait_for_subprocess() -> None:
        try:
            await proc.wait()
        except asyncio.CancelledError:
            pass
        finally:
            _shutdown_event.set()
    
    proc_task = asyncio.create_task(wait_for_subprocess(), name="proc_waiter")
    tasks.append(proc_task)
    
    # Wait for all tasks to complete
    try:
        await asyncio.gather(*tasks, return_exceptions=True)
    except asyncio.CancelledError:
        pass
    
    # Clean up: terminate subprocess if still running
    if proc.returncode is None:
        try:
            proc.terminate()
            await asyncio.wait_for(proc.wait(), timeout=5.0)
        except (asyncio.TimeoutError, ProcessLookupError):
            try:
                proc.kill()
            except ProcessLookupError:
                pass
    
    # Return Kimi's exit code
    return proc.returncode if proc.returncode is not None else 0


def run_bridge() -> int:
    """Synchronous entry point for the bridge.
    
    Returns:
        Exit code.
    """
    try:
        return asyncio.run(main())
    except KeyboardInterrupt:
        return 130  # Standard exit code for SIGINT
    except Exception as e:
        print(f"[bridge] Fatal error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(run_bridge())
