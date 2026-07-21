# YAML Schemas

MMCU uses YAML for project metadata and keeps schema descriptions in
`./yaml`. Schema enforcement is implemented with Python, PyYAML, and
Pydantic.

The intended validation stack is:

1. Load YAML with PyYAML or `pydantic-yaml`.
2. Validate the resulting Python data with Pydantic models.
3. Treat the YAML files in `./yaml` as the human-readable schema source
   used to design and test those Pydantic models.

This keeps the schema language, project metadata, and examples in the same
format while still using normal Python validation for type checks,
cross-field checks, URL parsing, and useful error messages.

## Schema Files

Current schemas:

| Schema | Applies to |
|---|---|
| `yaml/mmcu-board.schema.yaml` | `boards/*/mmcu-board.yaml` |
| `yaml/mmcu-board.yamale.yaml` | Optional Yamale structural check for `boards/*/mmcu-board.yaml` |

Validation tooling:

```sh
python3 -m pip install -r requirements-yaml.txt
python3 tools/validate-yaml.py
yamale -s yaml/mmcu-board.yamale.yaml boards
```

## Yamale

[Yamale](https://github.com/23andMe/Yamale) is an optional YAML schema
validator that can be useful for quick structural checks before data
reaches the Pydantic models. It is still YAML-first: Yamale schemas are
YAML files, and Yamale validates YAML documents directly.

Use Yamale for simple shape checks:

```sh
python3 -m pip install yamale
yamale -s yaml/mmcu-board.yamale.yaml boards/pico/mmcu-board.yaml
yamale -s yaml/mmcu-board.yamale.yaml boards
```

The `-s` option selects the schema file. When given a directory, Yamale
walks YAML files under that directory. By default Yamale runs in strict
mode, so unexpected fields fail validation; use that default for MMCU.

A Yamale schema for the current board shape would look like this:

```yaml
name: str()
target: str(required=False)
virtual: bool(required=False)
compatible_targets: list(str(), required=False)
power: include('power')
rails: list(num())
analog_io: include('analog_io', required=False)
digital_io: include('digital_io', required=False)
buses: list(enum('BLUETOOTH', 'CAN', 'ETHERNET', 'RS232', 'RS485', 'SD-CARD', 'USB', 'WIFI'))
connectors: list(str())
default_providers: map(str(), key=str(), required=False)
links: include('links', required=False)
---
power:
  regulation: enum('DC-DC', 'LDO', 'LDO;DC-DC')
  input_voltage_min: num()
  input_voltage_max: num()
analog_io:
  adc_channels_broken_out: int(min=0, required=False)
digital_io:
  gpio_broken_out: int(min=0, required=False)
  internal_pins: list(str(), required=False)
links:
  documentation: list(include('link'))
  support_repositories: list(include('link'))
link:
  label: str()
  url: str()
```

Yamale is not the final authority for MMCU because some rules are
cross-field rules: a real board must have `target` and must not have
`compatible_targets`; a virtual board must have `virtual: true` and
`compatible_targets` and must not have `target`; voltage minimum must be
less than or equal to voltage maximum. Keep those checks in Pydantic.

The practical split is:

| Tool | Role |
|---|---|
| Yamale | Optional fast structural validation of YAML shape |
| PyYAML | Parse YAML into Python data |
| pydantic-yaml | Parse YAML directly into Pydantic models and write models back as YAML |
| Pydantic | Enforce MMCU's full semantic contract and produce diagnostics |

## pydantic-yaml

[pydantic-yaml](https://github.com/NowanIlfideme/pydantic-yaml) adds YAML
read/write helpers around Pydantic models. Use it when the code wants the
YAML file and the Pydantic model to be the same API boundary.

Install it through the project YAML requirements:

```sh
python3 -m pip install -r requirements-yaml.txt
```

For board declarations, the basic pattern is:

```python
from pathlib import Path

from pydantic_yaml import parse_yaml_raw_as, to_yaml_str


def load_board(path: Path) -> BoardDecl:
    return parse_yaml_raw_as(BoardDecl, path.read_text(encoding="utf-8"))


def dump_board(board: BoardDecl) -> str:
    return to_yaml_str(board)
```

This is useful for future tools that need to rewrite YAML deterministically
after validation. For example, a formatter could load a board declaration
as `BoardDecl`, normalize ordering/defaults, and write YAML back out from
the model.

Keep the same division of responsibility:

| Tool | Use |
|---|---|
| `pydantic-yaml` | Convenient Pydantic model load/dump for YAML files |
| Pydantic model validators | Cross-field and semantic rules |
| `yaml/*.schema.yaml` | Human-readable schema contract |
| Yamale | Optional structural schema smoke test |

Schema files use this shape:

```yaml
schema: mmcu.schema/v1
name: mmcu-board
file_name: mmcu-board.yaml
applies_to:
  - boards/*/mmcu-board.yaml

rules:
  unknown_fields: reject

fields:
  name:
    type: str
    required: true
```

The schema file is not executable by itself. It records the contract that
the Python validator implements with Pydantic. The validator should reject
unknown fields unless a schema explicitly allows them.

## Pydantic Pattern

The implementation should model each YAML document with a Pydantic class.
For board declarations, that means a top-level `BoardDecl` model plus
nested models for `power`, `links`, and link entries.

The important rule is to validate after parsing:

```python
from pathlib import Path

import yaml
from pydantic import BaseModel, ConfigDict, Field, HttpUrl, model_validator


class Link(BaseModel):
    model_config = ConfigDict(extra="forbid")

    label: str
    url: HttpUrl


class Links(BaseModel):
    model_config = ConfigDict(extra="forbid")

    documentation: list[Link] = Field(min_length=1)
    support_repositories: list[Link] = Field(min_length=1)


class Power(BaseModel):
    model_config = ConfigDict(extra="forbid")

    regulation: str
    input_voltage_min: float
    input_voltage_max: float

    @model_validator(mode="after")
    def valid_voltage_range(self):
        if self.input_voltage_min > self.input_voltage_max:
            raise ValueError("input_voltage_min must be <= input_voltage_max")
        return self


class BoardDecl(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: str
    target: str | None = None
    virtual: bool = False
    compatible_targets: list[str] | None = None
    power: Power
    rails: list[float] = Field(min_length=1)
    buses: list[str]
    connectors: list[str] = Field(min_length=1)
    links: Links | None = None

    @model_validator(mode="after")
    def real_or_virtual_board(self):
        if self.virtual:
            if self.target is not None:
                raise ValueError("virtual boards use compatible_targets, not target")
            if not self.compatible_targets:
                raise ValueError("virtual boards require compatible_targets")
        else:
            if not self.target:
                raise ValueError("real boards require target")
            if self.compatible_targets is not None:
                raise ValueError("real boards must not set compatible_targets")
        return self


def load_board(path: Path) -> BoardDecl:
    with path.open("r", encoding="utf-8") as handle:
        data = yaml.safe_load(handle)
    return BoardDecl.model_validate(data)
```

The schema in `./yaml/mmcu-board.schema.yaml` exists so reviewers can see
the intended contract without reading Python code first. The Pydantic
model in `tools/validate-yaml.py` is the enforcement point.

## Board Schema

`boards/*/mmcu-board.yaml` supports two identities:

| Kind | Required | Forbidden |
|---|---|---|
| Real board | `name`, `target` | `compatible_targets` |
| Virtual board variant | `name`, `virtual: true`, `compatible_targets` | `target` |

Common fields:

| Field | Meaning |
|---|---|
| `power` | Regulation type and accepted input voltage range |
| `rails` | Board-supplied voltage rails |
| `analog_io` | Analog pins/channels actually broken out by the board |
| `digital_io` | GPIO and internal board-only pins |
| `buses` | Board-level buses/transceivers/radios exposed to dependency resolving |
| `connectors` | Physical or abstract connector profile |
| `default_providers` | Preferred provider package per board capability |
| `links.documentation` | Official documentation provenance |
| `links.support_repositories` | Official SDK/example/support repositories |

Virtual boards such as `pico-all` and `pico-w-all` are allowed to use
abstract connector names because they model a common profile rather than a
single purchasable PCB.
