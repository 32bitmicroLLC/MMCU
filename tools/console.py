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
    parser.add_argument("--diagnostic", action="store_true", help="trace terminal and serial events on stderr")
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
        stdin_fd = sys.stdin.fileno()
        serial_fd = connection.fileno()
        if args.diagnostic:
            print(f"diagnostic: stdin_fd={stdin_fd} serial_fd={serial_fd} tty={sys.stdin.isatty()}", file=sys.stderr)
        if sys.stdin.isatty():
            old_settings = termios.tcgetattr(stdin_fd)
            tty.setraw(stdin_fd)
        print(f"Connected to {args.port} at {args.baud} baud; Ctrl-] exits.", file=sys.stderr)
        while True:
            readable, _, _ = select.select([stdin_fd, serial_fd], [], [], 0.1)
            if serial_fd in readable:
                data = connection.read(connection.in_waiting or 1)
                if data:
                    if args.diagnostic:
                        print(f"diagnostic: received {len(data)} byte(s): {data.hex(' ')}", file=sys.stderr)
                    sys.stdout.buffer.write(data)
                    sys.stdout.buffer.flush()
            if stdin_fd in readable:
                data = os.read(stdin_fd, 1024)
                if not data:
                    break
                if args.diagnostic:
                    print(f"diagnostic: stdin {len(data)} byte(s): {data.hex(' ')}", file=sys.stderr)
                # Raw mode disables the terminal's normal SIGINT handling,
                # so Ctrl-C arrives as byte 0x03. Ctrl-] is the miniterm
                # escape byte (0x1d). Ctrl-D is also a useful emergency exit.
                exit_positions = [
                    pos for pos in
                    (data.find(b"\x03"), data.find(b"\x1d"), data.find(b"\x04"))
                    if pos >= 0
                ]
                if exit_positions:
                    data = data[: min(exit_positions)]
                    if data:
                        connection.write(data)
                    break
                if not args.raw:
                    # Raw terminals commonly report Enter as CR (0x0d),
                    # while pasted input may contain LF or CRLF. Normalize
                    # all three forms to CRLF for line-oriented targets.
                    data = data.replace(b"\r\n", b"\n")
                    data = data.replace(b"\r", b"\n")
                    data = data.replace(b"\n", b"\r\n")
                connection.write(data)
    except KeyboardInterrupt:
        pass
    finally:
        if old_settings is not None:
            termios.tcsetattr(stdin_fd, termios.TCSADRAIN, old_settings)
        connection.close()
        print("\nDisconnected.", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
