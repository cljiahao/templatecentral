"""Factory functions for creating test domain models with sensible defaults.

Usage:
    member = create_member(name="Alice")
    member = create_member()  # uses defaults
"""


def create_example_request(
    name: str = "World",
    repeat_count: int = 1,
) -> dict:
    """Create an example request payload."""
    return {
        "name": name,
        "repeatCount": repeat_count,
    }
