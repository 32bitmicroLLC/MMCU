# Drivers

`drivers/` holds drivers for discrete hardware peripherals and embedded
devices — sensors, motor/actuator controllers, storage chips, power
management ICs, RTCs, wireless radio modules, and the bus/interface
peripherals they're wired to — organized by topic, the same scheme
[Libraries](libraries.md) uses.

The distinction from `libraries/`: `libraries/<topic>/` organizes
protocol/format implementations (a bus *protocol*, a display technology, a
data format) — about *how you talk to something*. `drivers/<topic>/`
organizes drivers for *specific physical parts and peripherals* — an IMU, a
stepper driver, an I2C GPIO expander — each typically built on top of one
or more `libraries/` implementations and a `platforms/` foundation. A
driver in `drivers/Sensors/IMU/some-imu-driver/` might depend on a bus
helper living in `libraries/`.

```
drivers/
  Sensors/
    IMU/
    Temperature/
    Humidity/
    Pressure/
  Motor/
    Stepper/
    Servo/
    BLDC/
  Power/
    Regulator/
    Charger/
    FuelGauge/
  Storage/
    EEPROM/
    Flash/
    SDCard/
  RTC/
    <driver-name>/
  Wireless/
    BLE/
    WiFi/
    LoRa/
  SPI/
    <driver-name>/
  I2C/
    <driver-name>/
  GPIO/
    <driver-name>/
  ADC/
    <driver-name>/
```

## Two kinds of topic

Most topics above are **device categories** (`Sensors`, `Motor`, `Power`,
`Storage`, `RTC`, `Wireless`) — what the part fundamentally *is*.

`SPI`, `I2C`, `GPIO`, and `ADC` are **interface topics** — for drivers whose
identity is really the bus/pin peripheral itself rather than any one kind
of device: a generic I2C GPIO expander, a generic SPI-to-parallel shift
register, a generic ADC channel/mux driver. These come up often enough in
embedded work (drivers written once against "an I2C device at this
address" or "an ADC channel", reused across many different physical parts)
that they're peer topics in their own right, not sub-folders of the device
categories that happen to use them.

## Layout rule

```
drivers/<topic>/<driver-name>/
```

— or, only where a topic genuinely splits into distinct, non-interchangeable
device families (the way `Sensors` splits into `IMU`/`Temperature`/
`Humidity`/`Pressure`, or `Motor` into `Stepper`/`Servo`/`BLDC`):

```
drivers/<topic>/<sub-category>/<driver-name>/
```

Whatever's inside `<driver-name>/` is that driver's own layout — MMCU
doesn't impose further structure on it. Depth stays capped at this: one
topic level, an optional sub-category level only when the topic actually
needs it, then the driver itself. Interface topics (`SPI`/`I2C`/`GPIO`/
`ADC`) stay flat — they don't split into sub-categories.

A topic is a peer-level category in its own right (`Motor`, `Power`, `RTC`,
`SPI`, ...), not an umbrella grouping several unrelated ones together —
each stands alone at the top of `drivers/`; there is no `Interfaces/`
folder grouping `SPI`/`I2C`/`GPIO`/`ADC` together, the same way there's no
`networking/` grouping `libraries/CANbus`/`libraries/JSON` together.

## Choosing a topic for a new driver

- **It's fundamentally a kind of device** (a sensor, a motor driver, a
  power IC), regardless of which bus it happens to use: put it under that
  device category, not the interface it's wired to. An I2C-connected IMU
  still goes in `Sensors/IMU/`, not `I2C/`.
- **It's fundamentally about the interface, not any one device** (a
  generic I2C mux, a generic SPI GPIO expander, a raw ADC channel driver
  usable by many unrelated sensor types): put it under the matching
  interface topic (`I2C/`, `SPI/`, `GPIO/`, `ADC/`).
- **It's a variant of an existing topic's device family** (a new IMU part,
  a new stepper driver chip): add it under that topic's existing
  sub-category folder, or a new sub-category folder as needed
  (`Sensors/Gas/`, say).
- **It's a genuinely new category** (nothing existing fits, device or
  interface): add a new `drivers/<topic>/` at the top level.
- **It's a single-part topic with no natural split yet** (`RTC`): keep it
  flat as `drivers/RTC/<driver-name>/` until a second, genuinely distinct
  sub-category shows up.

## Drivers that belong to more than one topic

A driver's actual content lives in exactly one place — its **primary**
topic. Anywhere else it's also relevant, add a **relative symlink** back to
that primary location instead of copying or vendoring it twice. This comes
up often between a device category and the interface it's built on — e.g.
an I2C-based fuel gauge, primarily a `Power` part but also worth finding
under `I2C`:

```bash
cd drivers/I2C
ln -s ../Power/FuelGauge/some-fuel-gauge some-fuel-gauge
```

This keeps one canonical copy (no version drift between "copies" of the
same driver) while still making it discoverable/browsable from every topic
it's relevant to. When adding a driver that spans topics, decide the
primary topic first (the one it's most fundamentally *about* — usually the
device category over the interface), put the real directory there, and
symlink from the rest.

`drivers/` itself doesn't need to exist until the first driver lands in
it — it's created on demand, not scaffolded empty ahead of time.

## Expressing dependencies

How an application depends on a library, a library on a driver, and a
driver on a peripheral capability (and how the build system checks that
chain) is covered separately in
[Dependencies: Applications, Libraries, Drivers, Peripherals](dependencies.md).
