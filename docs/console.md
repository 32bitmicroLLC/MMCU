# Serial console

`console.sh` provides a small interactive USB serial terminal for boards that
expose a CDC ACM or UART device such as `/dev/ttyACM0`. It uses the project
virtual environment and pyserial, and follows the basic interaction model of
pyserial's `miniterm.py`.

Install the dependency and create the virtual environment with:

```bash
./setup.sh
```

Connect to a board at the default 115200 baud:

```bash
./console.sh /dev/ttyACM0
```

Choose another speed or enable hardware flow control:

```bash
./console.sh --baud 115200 --rtscts /dev/ttyUSB0
./console.sh --dsrdtr /dev/ttyACM0
```

If control keys or input appear not to work, enable diagnostics:

```bash
./console.sh --diagnostic /dev/ttyACM0
```

Diagnostics are written to stderr and show the file descriptors, whether
stdin is a terminal, bytes received from the board, and bytes read from the
keyboard. `Ctrl-C` should appear as `03` and `Ctrl-]` as `1d`. Stop the
diagnostic session with `Ctrl-D` or by closing the terminal.

The console passes received bytes directly to the terminal. Input newlines are
translated to CRLF by default; use `--raw` to disable that translation. Press
`Ctrl-]` or `Ctrl-C` to disconnect. The console handles both keys itself while
the terminal is in raw mode, so they work even though the usual terminal
signal processing is disabled.

Enter is normalized from CR, LF, or CRLF to CRLF. This is important for the
MCP server, which accepts newline-delimited JSON-RPC messages.

On Linux, the current user normally needs to be in the `dialout` group:

```bash
ls -l /dev/ttyACM0
sudo usermod -aG dialout "$USER"
```

Log out and back in after changing group membership. Use `./doctor.sh --target`
to discover Raspberry Pi USB serial devices, permissions, driver, and serial
number before starting the console.

`console.sh` does not reset, flash, or configure the target. Configure and
build with the normal MMCU workflow first, then use this tool to observe the
application's USB stdio output.
