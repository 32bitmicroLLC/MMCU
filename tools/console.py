#!/usr/bin/env python3
"""Small serial console based on pyserial's miniterm behavior."""

import argparse
import os
import select
import sys
import termios
import tty

def main() -> int:
    parser = argparse.ArgumentParser(description="Connect to a USB serial console")
    parser.add_argument("port", help="serial device, for example /dev/ttyACM0")
    parser.add_argument("-b", "--baud", type=int, default=115200)
    parser.add_argument("--rtscts", action="store_true")
    parser.add_argument("--dsrdtr", action="store_true")
    parser.add_argument("--raw", action="store_true", help="do not translate newlines")
    args = parser.parse_args()

    try:
        import serial
    except ImportError:
        print("console: pyserial is missing; run ./setup.sh", file=sys.stderr)
        return 1

    try:
        connection = serial.Serial(
            args.port, args.baud, timeout=0, rtscts=args.rtscts, dsrdtr=args.dsrdtr
        )
    except serial.SerialException as exc:
        print(f"console: cannot open {args.port}: {exc}", file=sys.stderr)
        return 1

    old_settings = None
    try:
        if sys.stdin.isatty():
            old_settings = termios.tcgetattr(sys.stdin.fileno())
            tty.setraw(sys.stdin.fileno())
        print(f"Connected to {args.port} at {args.baud} baud; Ctrl-] exits.", file=sys.stderr)
        while True:
            readable, _, _ = select.select([sys.stdin, connection], [], [], 0.1)
            if connection in readable:
                data = connection.read(connection.in_waiting or 1)
                if data:
                    sys.stdout.buffer.write(data)
                    sys.stdout.buffer.flush()
            if sys.stdin in readable:
                data = os.read(sys.stdin.fileno(), 1024)
                if not data:
                    break
                if b"\x1d" in data:
                    data = data.split(b"\x1d", 1)[0]
                    if data:
                        connection.write(data)
                    break
                if not args.raw:
                    data = data.replace(b"\n", b"\r\n")
                connection.write(data)
    except KeyboardInterrupt:
        pass
    finally:
        if old_settings is not None:
            termios.tcsetattr(sys.stdin.fileno(), termios.TCSADRAIN, old_settings)
        connection.close()
        print("\nDisconnected.", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
