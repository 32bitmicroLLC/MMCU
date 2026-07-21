# Libraries

`libraries/` holds functional/topical embedded libraries — display drivers,
bus/protocol implementations, sensor drivers, and similar — organized by
topic. This is separate from `platforms/` (see [Project Layout](layout.md)):
`platforms/<name>/` holds vendor SDK *foundations* that a target builds
against (pico-sdk, CMSIS), left exactly as they are; `libraries/<topic>/`
holds everything else a project might link in on top of a platform.

```
libraries/
  Display/
    TFT/
    LCD/
    ePaper/
    eInk/
    OLED/
  CANbus/
    <library-name>/
  JSON/
    JSON-RPC/
    <other JSON library>/
```

## Layout rule

```
libraries/<topic>/<library-name>/
```

— or, only where a topic genuinely splits into distinct, non-interchangeable
technologies (the way `Display` splits into `TFT`/`LCD`/`ePaper`/`eInk`/
`OLED`, each with its own driver family):

```
libraries/<topic>/<sub-technology>/<library-name>/
```

Whatever's inside `<library-name>/` is that library's own layout (its own
source tree, or a vendored checkout) — MMCU doesn't impose further structure
on it. Depth stays capped at this: one topic level, an optional
sub-technology level only when the topic actually needs it, then the
library itself.

A topic is a peer-level communication/interface/technology category in its
own right (`CANbus`, `JSON`), not an umbrella grouping several unrelated
ones together (there is no `networking/` or `rpc/` grouping `CANbus`/
`Modbus`/`JSON-RPC`/`MQTT` under one folder) — each stands alone at the top
of `libraries/`.

## Choosing a topic for a new library

- **It's a genuinely new topic** (nothing existing fits): add a new
  `libraries/<topic>/` at the top level.
- **It's a variant of an existing topic's technology** (a new OLED driver,
  a new TFT controller): add it under that topic's existing sub-technology
  folder, or a new sub-technology folder as needed (`Display/MicroLED/`,
  say).
- **It's JSON-flavored, or CAN-flavored, etc.**: goes under that existing
  topic (`JSON/`, `CANbus/`), not a new topic of its own — `JSON-RPC` lives
  at `libraries/JSON/JSON-RPC/`, not `libraries/JSON-RPC/`.

## Libraries that belong to more than one topic

A library's actual content lives in exactly one place — its **primary**
topic. Anywhere else it's also relevant, add a **relative symlink** back to
that primary location instead of copying or vendoring it twice:

```bash
cd libraries/CANbus
ln -s ../JSON/JSON-RPC/some-can-rpc-bridge some-can-rpc-bridge
```

This keeps one canonical copy (no version drift between "copies" of the
same library) while still making it discoverable/browsable from every topic
it's relevant to. When adding a library that spans topics, decide the
primary topic first (the one it's most fundamentally *about*), put the real
directory there, and symlink from the rest.

`libraries/` itself doesn't need to exist until the first library lands in
it — it's created on demand, not scaffolded empty ahead of time.
