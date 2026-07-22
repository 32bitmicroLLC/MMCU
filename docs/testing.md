# Testing MMCU applications

MMCU application tests have two layers:

1. host/build tests validate manifests, compilation, and generated artifacts;
2. target tests exercise a flashed application through its platform transport.

Target tests are hardware-in-the-loop and are not run by the normal native or
cross-compilation build.

## Test dispatcher

`test.sh` selects the test entry point belonging to the application recorded by
`configure.sh` in `.config`. It prefers an application-local `test.sh`, then
the first `test-*.py` script:

```bash
./test.sh --list
./test.sh --verbose /dev/ttyACM0
```

Use explicit application or build directory overrides when testing a
configuration other than the current `.config`:

```bash
./test.sh --application-dir applications/mcp/server \
  --build-dir build-rp2040-gcc /dev/ttyACM0
```

Positional arguments, and arguments after `--`, are passed to the application test. Applications without
an entry point are reported as untested; `test.sh` does not invent a test or
flash hardware automatically.

## MCP server USB smoke test

Configure and build the MCP application with USB stdio, then flash and reboot
the board:

```bash
./configure.sh -i
# select applications/mcp/server, pico_sdk, rp2040, and stdio usb
./build.sh
./run.sh
```

Find the USB serial device with:

```bash
./doctor.sh --target
```

Run the formal application test:

```bash
./applications/mcp/server/test-console.py /dev/ttyACM0
```

The test invokes the same console transport used interactively:

```bash
./console.sh --request '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
  --wait-response 2 /dev/ttyACM0
```

It sends one newline-delimited JSON-RPC request, waits up to two seconds, parses
the response, and verifies that the response ID is `1` and contains a result.
Use `--wait 5` for a board that takes longer to enumerate.

Manual follow-up requests can be sent with `console.sh --diagnostic`; press
Enter after each JSON line. `Ctrl-]` or `Ctrl-C` exits interactive mode.

## Test requirements

- the application must be flashed to the expected board;
- USB CDC stdio must be selected;
- the current user must have permission to open `/dev/ttyACM0` (usually the
  `dialout` group on Linux);
- only one console or test process may own the serial device;
- target tests should be run after `./doctor.sh --target` reports a visible
  Raspberry Pi USB serial device.

An unavailable device or timeout is a failed target test, not a skipped build
test. CI may mark it as an infrastructure failure when no hardware fixture is
attached.
