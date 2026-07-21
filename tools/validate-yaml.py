#!/usr/bin/env python3
"""Validate MMCU YAML metadata using PyYAML and Pydantic."""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Any, Literal

import yaml
from pydantic import BaseModel, ConfigDict, Field, HttpUrl, model_validator


ROOT = Path(__file__).resolve().parents[1]


class Link(BaseModel):
    model_config = ConfigDict(extra="forbid")

    label: str = Field(min_length=1)
    url: HttpUrl


class Links(BaseModel):
    model_config = ConfigDict(extra="forbid")

    documentation: list[Link] = Field(min_length=1)
    support_repositories: list[Link] = Field(min_length=1)


class Power(BaseModel):
    model_config = ConfigDict(extra="forbid")

    regulation: Literal["DC-DC", "LDO", "LDO;DC-DC"]
    input_voltage_min: float
    input_voltage_max: float

    @model_validator(mode="after")
    def valid_voltage_range(self) -> "Power":
        if self.input_voltage_min > self.input_voltage_max:
            raise ValueError("input_voltage_min must be <= input_voltage_max")
        return self


class AnalogIo(BaseModel):
    model_config = ConfigDict(extra="forbid")

    adc_channels_broken_out: int | None = Field(default=None, ge=0)


class DigitalIo(BaseModel):
    model_config = ConfigDict(extra="forbid")

    gpio_broken_out: int | None = Field(default=None, ge=0)
    internal_pins: list[str] | None = None

    @model_validator(mode="after")
    def unique_internal_pins(self) -> "DigitalIo":
        if self.internal_pins and len(self.internal_pins) != len(set(self.internal_pins)):
            raise ValueError("internal_pins must not contain duplicates")
        return self


class BoardDecl(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: str = Field(pattern=r"^[a-z0-9][a-z0-9-]*$")
    target: str | None = Field(default=None, pattern=r"^[a-z0-9][a-z0-9-]*$")
    virtual: bool = False
    compatible_targets: list[str] | None = None
    power: Power
    rails: list[float] = Field(min_length=1)
    analog_io: AnalogIo | None = None
    digital_io: DigitalIo | None = None
    buses: list[
        Literal[
            "BLUETOOTH",
            "CAN",
            "ETHERNET",
            "RS232",
            "RS485",
            "SD-CARD",
            "USB",
            "WIFI",
        ]
    ]
    connectors: list[str] = Field(min_length=1)
    default_providers: dict[str, str] | None = None
    links: Links | None = None

    @model_validator(mode="after")
    def real_or_virtual_board(self) -> "BoardDecl":
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

    @model_validator(mode="after")
    def unique_lists(self) -> "BoardDecl":
        for field_name in ("compatible_targets", "rails", "buses", "connectors"):
            values = getattr(self, field_name)
            if values and len(values) != len(set(values)):
                raise ValueError(f"{field_name} must not contain duplicates")
        return self


def load_yaml(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def validate_board(path: Path) -> None:
    BoardDecl.model_validate(load_yaml(path))


def main() -> int:
    paths = [Path(arg) for arg in sys.argv[1:]]
    if not paths:
        paths = sorted((ROOT / "boards").glob("*/mmcu-board.yaml"))

    failures = 0
    for path in paths:
        try:
            validate_board(path)
        except Exception as exc:  # noqa: BLE001 - keep CLI diagnostics compact.
            failures += 1
            print(f"{path}: {exc}", file=sys.stderr)
        else:
            print(f"{path}: ok")

    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
