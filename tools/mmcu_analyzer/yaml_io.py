"""YAML load/dump helpers shared by the analyzer.

Canonical output is YAML, never JSON. Key order is stable: it follows the
order fields are declared on the Pydantic model, since ``model_dump()``
preserves declaration order and we never sort keys when dumping.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any, TypeVar

import yaml
from pydantic import BaseModel

ModelT = TypeVar("ModelT", bound=BaseModel)


def load_yaml(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def load_model(path: Path, model_cls: type[ModelT]) -> ModelT:
    data = load_yaml(path)
    if data is None:
        data = {}
    return model_cls.model_validate(data)


def write_yaml(path: Path, model_or_dict: BaseModel | dict[str, Any]) -> None:
    if isinstance(model_or_dict, BaseModel):
        data = model_or_dict.model_dump(mode="json", by_alias=True, exclude_none=True)
    else:
        data = model_or_dict
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        yaml.safe_dump(
            data,
            handle,
            sort_keys=False,
            default_flow_style=False,
            allow_unicode=True,
        )
