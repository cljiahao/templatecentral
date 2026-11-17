from dataclasses import dataclass


@dataclass(slots=True)
class BaseModel:
    """Base for mutable domain models."""


@dataclass(frozen=True, slots=True)
class BaseImmutableModel:
    """Base for immutable domain models."""
