#!/usr/bin/env python3
"""Hardware smoke test for the MCP server over USB CDC."""

import argparse
import json
import pathlib
import subprocess
import sys


def main() -> int:
    parser = argparse.ArgumentParser(description="Test the flashed MMCU MCP server")
    parser.add_argument("port", help="serial device, for example /dev/ttyACM0")
    parser.add_argument("--wait", type=float, default=2.0)
    parser.add_argument("--build-dir", help="accepted by test.sh for dispatcher compatibility")
    args = parser.parse_args()

    root = pathlib.Path(__file__).resolve().parents[3]
    request = {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}}
    command = [
        str(root / "console.sh"),
        "--request", json.dumps(request, separators=(",", ":")),
        "--wait-response", str(args.wait),
        args.port,
    ]
    result = subprocess.run(command, cwd=root, text=True, capture_output=True)
    if result.returncode != 0:
        sys.stderr.write(result.stderr)
        return result.returncode
    try:
        response = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        print(f"MCP test: invalid JSON response: {exc}", file=sys.stderr)
        print(result.stdout, file=sys.stderr)
        return 1
    if response.get("id") != 1 or "result" not in response:
        print(f"MCP test: unexpected response: {response}", file=sys.stderr)
        return 1
    print("MCP initialize: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
