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

The console passes received bytes directly to the terminal. Input newlines are
translated to CRLF by default; use `--raw` to disable that translation. Press
`Ctrl-]` to disconnect. `Ctrl-C` also exits cleanly.

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
