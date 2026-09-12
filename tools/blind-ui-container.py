#!/usr/bin/env python3
"""Staff-only offline recorder controls. No UI automation and no message sending."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import uuid


def uuid_value(value):
    return str(uuid.UUID(value))


def read_json(path):
    if path.is_symlink() or not path.is_file() or path.stat().st_size > 2_097_152:
        raise ValueError("Missing or invalid fixture file")
    return json.loads(path.read_text())


def atomic(path, value):
    fd, temporary = tempfile.mkstemp(prefix=".recorder-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as output:
            json.dump(value, output, sort_keys=True)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
        directory_fd = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def await_receipt(path, expected, timeout):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if path.exists():
            receipt = read_json(path)
            if all(receipt.get(key) == value for key, value in expected.items()):
                return receipt
        time.sleep(0.05)
    raise TimeoutError("No matching fixture acknowledgement; do not retry a UI action")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulator", type=uuid_value, required=True)
    parser.add_argument("--run-id", type=uuid_value, required=True)
    parser.add_argument("--timeout", type=float, default=10)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("locate")
    commands.add_parser("status")
    action = commands.add_parser("context")
    action.add_argument("--action-id", type=uuid_value, required=True)
    action.add_argument("--sequence", type=int, required=True)
    close = commands.add_parser("close")
    close.add_argument("--command-id", type=uuid_value, required=True)
    args = parser.parse_args()
    if not 0 < args.timeout <= 60:
        parser.error("timeout must be in (0, 60]")
    container = Path(subprocess.check_output([
        "xcrun", "simctl", "get_app_container", args.simulator,
        "dev.alex.porch.blindui", "data"], text=True).strip())
    root = container / "Library/Application Support/PorchBlindUI" / args.run_id
    if not root.is_dir() or root.is_symlink():
        raise ValueError("Launch this run on this simulator before recording")
    sink = read_json(root / "sink.json")
    if sink.get("run_id") != args.run_id or sink.get("schema") != "blind-ui/sink-v1":
        raise ValueError("Fixture run identity mismatch")
    if args.command == "locate":
        print(json.dumps({"directory": str(root), "sink": str(root / "sink.json"),
            "attempts": str(root / "attempts.jsonl"), "diagnostics": str(root / "Diagnostics")}))
    elif args.command == "status":
        print(json.dumps({"run_id": args.run_id, "complete": sink.get("complete"),
            "accepted_writes": len(sink.get("writes", [])), "closed_receipt": (root / "closed.json").is_file()}))
    elif args.command == "context":
        if not 1 <= args.sequence <= 100_000:
            parser.error("sequence must be between 1 and 100000")
        expected = {"run_id": args.run_id, "action_id": args.action_id, "broker_sequence": args.sequence}
        atomic(root / "action-context.json", {"schema": "blind-ui/action-context-v1", **expected})
        receipt = await_receipt(root / "action-context-ack.json",
            {"schema": "blind-ui/action-context-ack-v1", **expected}, args.timeout)
        print(json.dumps(receipt, sort_keys=True))
    elif args.command == "close":
        expected = {"run_id": args.run_id, "command_id": args.command_id}
        atomic(root / "control.json", {"schema": "blind-ui/control-v1", "command": "close", **expected})
        receipt = await_receipt(root / "closed.json", {"schema": "blind-ui/closed-v1", **expected}, args.timeout)
        sink = read_json(root / "sink.json")
        complete = receipt.get("complete") is True and sink.get("complete") is True
        print(json.dumps({**receipt, "accepted_writes": len(sink.get("writes", [])), "complete": complete}, sort_keys=True))
        return 0 if complete else 2
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, TimeoutError, subprocess.CalledProcessError) as error:
        raise SystemExit(f"Fixture recording invalid: {error}")
