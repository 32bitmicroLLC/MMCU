# MCP

`mcp` is a self-contained Model Context Protocol server module for MMCU
applications that communicate over a line-oriented `stdio` transport.

The initial implementation intentionally keeps JSON and JSON-RPC handling
inside this module. A separate `json-rpc` library can be extracted later if
another protocol needs the same substrate.

