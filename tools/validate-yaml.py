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


def safe_relative_path(value: str) -> str:
    path = Path(value)
    if path.is_absolute() or ".." in path.parts:
        raise ValueError("path must be relative and must not contain '..'")
    return value


class BoardCollectionRef(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: str = Field(pattern=r"^[a-z0-9][a-z0-9-]*$")
    title: str = Field(min_length=1)
    path: str = Field(min_length=1)

    @model_validator(mode="after")
    def relative_path(self) -> "BoardCollectionRef":
        safe_relative_path(self.path)
        return self


class BoardRegistry(BaseModel):
    model_config = ConfigDict(extra="forbid")

    schema_: Literal["mmcu.board-collections/v1"] = Field(alias="schema")
    name: str = Field(pattern=r"^[a-z0-9][a-z0-9-]*$")
    description: str | None = None
    collections: list[BoardCollectionRef] = Field(min_length=1)

    @model_validator(mode="after")
    def unique_collections(self) -> "BoardRegistry":
        names = [collection.name for collection in self.collections]
        paths = [collection.path for collection in self.collections]
        if len(names) != len(set(names)):
            raise ValueError("collections must not contain duplicate names")
        if len(paths) != len(set(paths)):
            raise ValueError("collections must not contain duplicate paths")
        return self


class BoardRef(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: str = Field(pattern=r"^[a-z0-9][a-z0-9-]*$")
    path: str = Field(min_length=1)

    @model_validator(mode="after")
    def relative_path(self) -> "BoardRef":
        safe_relative_path(self.path)
        return self


class BoardCollection(BaseModel):
    model_config = ConfigDict(extra="forbid")

    schema_: Literal["mmcu.boards/v1"] = Field(alias="schema")
    name: str = Field(pattern=r"^[a-z0-9][a-z0-9-]*$")
    title: str = Field(min_length=1)
    vendor: str | None = None
    description: str | None = None
    boards: list[BoardRef] = Field(min_length=1)
    links: Links | None = None

    @model_validator(mode="after")
    def unique_boards(self) -> "BoardCollection":
        names = [board.name for board in self.boards]
        paths = [board.path for board in self.boards]
        if len(names) != len(set(names)):
            raise ValueError("boards must not contain duplicate names")
        if len(paths) != len(set(paths)):
            raise ValueError("boards must not contain duplicate paths")
        return self


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
    platforms: list[Literal["native", "mcu", "pico_sdk"]] = Field(min_length=1)
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
        for field_name in ("compatible_targets", "platforms", "rails", "buses", "connectors"):
            values = getattr(self, field_name)
            if values and len(values) != len(set(values)):
                raise ValueError(f"{field_name} must not contain duplicates")
        return self


def load_yaml(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def validate_board(path: Path) -> None:
    BoardDecl.model_validate(load_yaml(path))


def validate_board_collection(path: Path) -> BoardCollection:
    collection = BoardCollection.model_validate(load_yaml(path))
    for board in collection.boards:
        board_path = path.parent / board.path
        if not board_path.exists():
            raise ValueError(f"listed board '{board.name}' is missing: {board_path}")
        declaration = BoardDecl.model_validate(load_yaml(board_path))
        if declaration.name != board.name:
            raise ValueError(
                f"{board_path}: board name '{declaration.name}' "
                f"does not match collection entry '{board.name}'"
            )
    return collection


def validate_board_registry(path: Path) -> BoardRegistry:
    registry = BoardRegistry.model_validate(load_yaml(path))
    board_names: set[str] = set()
    for collection_ref in registry.collections:
        collection_path = path.parent / collection_ref.path
        if not collection_path.exists():
            raise ValueError(f"listed collection '{collection_ref.name}' is missing: {collection_path}")
        collection = validate_board_collection(collection_path)
        if collection.name != collection_ref.name:
            raise ValueError(
                f"{collection_path}: collection name '{collection.name}' "
                f"does not match registry entry '{collection_ref.name}'"
            )
        for board in collection.boards:
            if board.name in board_names:
                raise ValueError(f"duplicate board name across collections: {board.name}")
            board_names.add(board.name)
    return registry


def validate_path(path: Path) -> None:
    data = load_yaml(path)
    if not isinstance(data, dict):
        raise ValueError("YAML document must be a mapping")
    schema = data.get("schema")
    if schema == "mmcu.board-collections/v1":
        validate_board_registry(path)
    elif schema == "mmcu.boards/v1":
        validate_board_collection(path)
    elif path.name == "mmcu-board.yaml":
        BoardDecl.model_validate(data)
    else:
        raise ValueError(f"unsupported YAML document for validator: {path}")


def main() -> int:
    paths = [Path(arg) for arg in sys.argv[1:]]
    if not paths:
        registry = ROOT / "boards" / "mmcu-boards.yaml"
        paths = [registry] if registry.exists() else sorted((ROOT / "boards").rglob("mmcu-board.yaml"))

    failures = 0
    for path in paths:
        try:
            validate_path(path)
        except Exception as exc:  # noqa: BLE001 - keep CLI diagnostics compact.
            failures += 1
            print(f"{path}: {exc}", file=sys.stderr)
        else:
            print(f"{path}: ok")

    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
