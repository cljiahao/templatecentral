import logging

from core.logging import _redact_sensitive, setup_logging


def test_setup_logging_is_idempotent() -> None:
    setup_logging()
    first = len(logging.getLogger().handlers)
    setup_logging()
    assert len(logging.getLogger().handlers) == first
    assert first >= 1


def test_sensitive_keys_are_redacted_recursively() -> None:
    event = {"password": "hunter2", "user": {"token": "abc"}, "path": "/x"}
    result = _redact_sensitive(None, "info", event)
    assert result["password"] == "***"
    assert result["user"]["token"] == "***"
    assert result["path"] == "/x"
