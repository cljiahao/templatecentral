from dataclasses import dataclass


@dataclass(slots=True)
class BaseModel:
    """Base for mutable domain models (state that changes during processing)."""


@dataclass(frozen=True, slots=True)
class BaseImmutableModel:
    """Base for immutable domain models (config, lookup data, parameters)."""
