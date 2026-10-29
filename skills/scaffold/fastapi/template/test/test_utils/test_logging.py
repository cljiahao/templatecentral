"""Tests for the structlog configuration in core.logging."""

import logging

import pytest

from core.logging import _redact_sensitive, logger, setup_logging


@pytest.mark.unit
def test_logger_supports_structured_calls() -> None:
    """The exported logger binds context and exposes structlog methods."""
    bound = logger.bind(request_id="test-123")
    assert hasattr(bound, "info")
    assert hasattr(bound, "exception")


@pytest.mark.unit
def test_setup_logging_is_idempotent() -> None:
    """Re-running setup_logging replaces root handlers rather than stacking them."""
    setup_logging()
    first = len(logging.getLogger().handlers)
    setup_logging()
    assert len(logging.getLogger().handlers) == first
    assert first >= 1


@pytest.mark.unit
def test_sensitive_keys_are_redacted_recursively() -> None:
    """The redaction processor masks sensitive keys at any nesting depth."""
    event = {"password": "hunter2", "user": {"token": "abc"}, "path": "/x"}
    result = _redact_sensitive(None, "info", event)
    assert result["password"] == "***"
    assert result["user"]["token"] == "***"
    assert result["path"] == "/x"
