#!/usr/bin/env python3
"""Mock Kimi Wire server for testing.

This script simulates Kimi's JSON-RPC 2.0 Wire protocol output for testing
the bridge. It emits line-delimited JSON messages to stdout and can read
responses from stdin for interactive scenarios like ApprovalRequest.

Usage:
    mock-wire-server.py --turns N          # Emit N complete turn cycles
    mock-wire-server.py --approval         # Include approval request after turn
    mock-wire-server.py --rapid            # Rapid successive TurnEnd events
    mock-wire-server.py --empty            # Include empty turns
    mock-wire-server.py --idle-timeout N   # Simulate idle timeout after N seconds
"""

from __future__ import annotations

import argparse
import json
import random
import sys
import time
from typing import Any


# Sample content messages for ContentPart events
SAMPLE_CONTENTS = [
    "I've refactored the authentication module and added comprehensive unit tests.",
    "The database migration has been completed successfully. All tables are now updated.",
    "Fixed the bug in the user registration flow. The validation now works correctly.",
    "Created a new API endpoint for the analytics dashboard with proper error handling.",
    "Updated the documentation with examples for the new configuration options.",
    "Optimized the query performance by adding indexes to the users table.",
    "Deployed the changes to staging environment. All health checks passed.",
    "Resolved the merge conflicts in the feature branch. Ready for code review.",
]

# Sample actions for ApprovalRequest
SAMPLE_ACTIONS = [
    "run shell command: npm test",
    "run shell command: git push origin main",
    "execute: docker build -t myapp:latest .",
    "run shell command: pip install -r requirements.txt",
    "execute: make clean && make all",
    "run shell command: cargo test --release",
]


def emit(method: str, params: dict[str, Any], msg_id: str | int | None = None) -> None:
    """Emit a JSON-RPC 2.0 message to stdout.
    
    Args:
        method: JSON-RPC method name.
        params: Method parameters.
        msg_id: Optional message ID for requests.
    """
    msg: dict[str, Any] = {
        "jsonrpc": "2.0",
        "method": method,
        "params": params
    }
    if msg_id is not None:
        msg["id"] = msg_id
    
    print(json.dumps(msg), flush=True)


def emit_initialize() -> None:
    """Emit protocol initialization."""
    emit("initialize", {
        "protocolVersion": "2.0",
        "capabilities": {"events": ["TurnBegin", "TurnEnd", "ContentPart", "ToolCall"]}
    })


def emit_turn_begin(turn_num: int = 1) -> None:
    """Emit TurnBegin event."""
    emit("event", {
        "type": "TurnBegin",
        "payload": {"turn": turn_num}
    })


def emit_content_part(content: str) -> None:
    """Emit ContentPart event with text content."""
    emit("event", {
        "type": "ContentPart",
        "payload": {"content": content, "text": content}
    })


def emit_tool_call(name: str, args: dict[str, Any]) -> None:
    """Emit ToolCall event."""
    emit("event", {
        "type": "ToolCall",
        "payload": {"name": name, "arguments": args}
    })


def emit_turn_end() -> None:
    """Emit TurnEnd event."""
    emit("event", {
        "type": "TurnEnd",
        "payload": {}
    })


def emit_step_interrupted(reason: str = "user") -> None:
    """Emit StepInterrupted event."""
    emit("event", {
        "type": "StepInterrupted",
        "payload": {"reason": reason}
    })


def emit_approval_request(
    action: str = "run shell command: npm test",
    sender: str = "Shell",
    req_id: str = "approval-1"
) -> None:
    """Emit ApprovalRequest (this is a request, requires response).
    
    After emitting, the server will wait for a JSON-RPC response on stdin.
    """
    emit("request", {
        "type": "ApprovalRequest",
        "payload": {
            "id": req_id,
            "tool_call_id": f"tc-{req_id}",
            "sender": sender,
            "action": action
        }
    }, msg_id=req_id)


def emit_status_update(status: str, message: str = "") -> None:
    """Emit StatusUpdate event."""
    emit("event", {
        "type": "StatusUpdate",
        "payload": {"status": status, "message": message}
    })


def emit_response(result: Any, msg_id: str | int) -> None:
    """Emit a JSON-RPC response.
    
    This simulates Kimi sending a response to a client request.
    """
    msg: dict[str, Any] = {
        "jsonrpc": "2.0",
        "result": result,
        "id": msg_id
    }
    print(json.dumps(msg), flush=True)


def wait_for_response(timeout: float = 30.0) -> dict[str, Any] | None:
    """Wait for and read a JSON-RPC response from stdin.
    
    Args:
        timeout: Maximum time to wait in seconds.
        
    Returns:
        The parsed response, or None if timeout/EOF.
    """
    # In mock mode, we don't block indefinitely
    start = time.monotonic()
    while time.monotonic() - start < timeout:
        try:
            line = sys.stdin.readline()
            if not line:
                return None
            return json.loads(line)
        except json.JSONDecodeError:
            continue
        except EOFError:
            return None
    return None


def simulate_full_turn(
    turn_num: int,
    with_content: bool = True,
    with_tool_call: bool = False,
    content_text: str | None = None
) -> None:
    """Simulate a complete turn cycle.
    
    Args:
        turn_num: Turn number for tracking.
        with_content: Whether to include ContentPart.
        with_tool_call: Whether to include a ToolCall.
        content_text: Optional specific content text.
    """
    # TurnBegin
    emit_turn_begin(turn_num)
    time.sleep(0.1)
    
    # ContentPart (if requested)
    if with_content:
        text = content_text or random.choice(SAMPLE_CONTENTS)
        emit_content_part(text)
        time.sleep(0.1)
    
    # ToolCall (if requested)
    if with_tool_call:
        emit_tool_call("read_file", {"path": "/tmp/test.txt"})
        time.sleep(0.05)
    
    # TurnEnd
    emit_turn_end()


def simulate_empty_turn(turn_num: int) -> None:
    """Simulate an empty turn (no content parts)."""
    simulate_full_turn(turn_num, with_content=False)


def simulate_approval_scenario(turn_num: int) -> dict[str, Any] | None:
    """Simulate a turn followed by an approval request.
    
    Emits a complete turn, then sends an ApprovalRequest and waits for
    the bridge to forward the response.
    
    Returns:
        The response received, if any.
    """
    # Complete a turn first
    simulate_full_turn(turn_num, with_content=True)
    time.sleep(0.2)
    
    # Send approval request
    action = random.choice(SAMPLE_ACTIONS)
    emit_approval_request(action=action, req_id=f"approval-{turn_num}")
    
    # Wait for response (bridge should forward user input as JSON-RPC response)
    return wait_for_response(timeout=5.0)


def simulate_rapid_turns(count: int) -> None:
    """Simulate rapid successive turns for debounce testing.
    
    Emits multiple TurnEnd events in quick succession to test
    the bridge's debounce logic.
    
    Args:
        count: Number of rapid turns to emit.
    """
    for i in range(count):
        emit_turn_begin(i + 1)
        emit_content_part(f"Quick update {i + 1}")
        emit_turn_end()
        # Very short delay to trigger debounce
        time.sleep(0.05)


def run_server(args: argparse.Namespace) -> None:
    """Main server loop.
    
    Args:
        args: Parsed command line arguments.
    """
    # Emit initialization
    emit_initialize()
    time.sleep(0.1)
    
    turns_to_emit = args.turns
    approval_after = args.approval
    
    for turn_num in range(1, turns_to_emit + 1):
        # Check if this should be an empty turn
        if args.empty and turn_num % 3 == 0:
            simulate_empty_turn(turn_num)
        # Check if this should include an approval request
        elif approval_after and turn_num == turns_to_emit:
            response = simulate_approval_scenario(turn_num)
            if response:
                # Echo the response back as an event
                emit("event", {
                    "type": "ApprovalResponse",
                    "payload": response
                })
        else:
            # Regular turn with content
            simulate_full_turn(
                turn_num,
                with_content=True,
                with_tool_call=(turn_num % 2 == 0)
            )
        
        # Delay between turns
        time.sleep(0.2)
    
    # Simulate rapid turns if requested
    if args.rapid:
        time.sleep(0.5)
        simulate_rapid_turns(5)
    
    # Keep running for idle timeout testing if requested
    if args.idle_timeout > 0:
        time.sleep(args.idle_timeout)
        emit_status_update("waiting", "Waiting for user input")
    
    # Emit final status
    emit_status_update("complete", "All turns completed")


def main() -> int:
    """Main entry point.
    
    Returns:
        Exit code.
    """
    parser = argparse.ArgumentParser(
        description="Mock Kimi Wire server for testing",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s --turns 3                    # Emit 3 complete turn cycles
  %(prog)s --turns 2 --approval         # 2 turns with approval request
  %(prog)s --turns 5 --rapid            # Include rapid turn burst
  %(prog)s --turns 3 --empty            # Mix in some empty turns
  %(prog)s --idle-timeout 10            # Simulate 10s idle period
"""
    )
    
    parser.add_argument(
        "--turns",
        type=int,
        default=1,
        help="Number of complete turn cycles to emit (default: 1)"
    )
    parser.add_argument(
        "--approval",
        action="store_true",
        help="Include an approval request after the last turn"
    )
    parser.add_argument(
        "--rapid",
        action="store_true",
        help="Emit rapid successive turns for debounce testing"
    )
    parser.add_argument(
        "--empty",
        action="store_true",
        help="Include empty turns (TurnBegin -> TurnEnd with no content)"
    )
    parser.add_argument(
        "--idle-timeout",
        type=int,
        default=0,
        help="Keep running for N seconds after turns (for idle testing)"
    )
    parser.add_argument(
        "--version",
        action="version",
        version="%(prog)s 1.0.0"
    )
    
    args = parser.parse_args()
    
    try:
        run_server(args)
        return 0
    except KeyboardInterrupt:
        # Clean shutdown
        emit_status_update("interrupted", "Server stopped by user")
        return 130
    except Exception as e:
        emit("event", {
            "type": "Error",
            "payload": {"message": str(e)}
        })
        return 1


if __name__ == "__main__":
    sys.exit(main())
