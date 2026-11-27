import logging
import logging.handlers
import sys
from datetime import datetime as dt
from pathlib import Path
from typing import Any

import structlog

from core.config import common_settings
from core.directory_manager import directory_manager as dm

# Keys redacted anywhere in a log event; extend for your domain.
_SENSITIVE_KEYS = {
    "password",
    "token",
    "access_token",
    "refresh_token",
    "authorization",
    "cookie",
    "set-cookie",
    "secret",
    "api_key",
}


def _redact_sensitive(
    _logger: Any, _method_name: str, event_dict: dict[str, Any]
) -> dict[str, Any]:
    """Redact sensitive values by key, recursing into nested dicts and sequences."""

    def scrub(value: Any) -> Any:
        if isinstance(value, dict):
            return {
                k: ("***" if k.lower() in _SENSITIVE_KEYS else scrub(v))
                for k, v in value.items()
            }
        if isinstance(value, (list, tuple)):
            return [scrub(v) for v in value]
        return value

    return scrub(event_dict)


class MyTimedRotatingFileHandler(logging.handlers.TimedRotatingFileHandler):
    """Custom log handler that rotates log files daily and organizes them by month."""

    def __init__(self, **kwargs: Any) -> None:
        super().__init__(**kwargs)
        self.namer = self.change_name

    def change_name(self, default_name: str) -> str:
        """Change the log filename to include the current month and year."""
        file_path = Path(default_name)
        tail = file_path.name

        mth_fol = dm.log_dir / dt.now().strftime("%b%Y")
        dm.create_directory(mth_fol)

        arr = tail.split(".")
        ext = arr.pop()
        fname = "_".join(arr) + f".{ext}"

        return str(mth_fol / fname)


# Processors shared by structlog and stdlib logs so both render identically.
_shared_processors: list[Any] = [
    structlog.contextvars.merge_contextvars,
    structlog.stdlib.add_logger_name,
    structlog.stdlib.add_log_level,
    structlog.stdlib.PositionalArgumentsFormatter(),
    structlog.processors.TimeStamper(fmt="iso"),
    structlog.processors.StackInfoRenderer(),
    structlog.processors.UnicodeDecoder(),
    _redact_sensitive,
]


# One ProcessorFormatter renders structlog and stdlib records; dev writes JSON files, prod/uat log JSON to stdout.
def setup_logging() -> None:
    """Configure structlog + stdlib logging: JSON in prod/uat, colored console in dev."""
    env = common_settings.ENVIRONMENT
    use_json = env != "dev"

    structlog.configure(
        processors=[
            *_shared_processors,
            structlog.stdlib.ProcessorFormatter.wrap_for_formatter,
        ],
        logger_factory=structlog.stdlib.LoggerFactory(),
        wrapper_class=structlog.stdlib.BoundLogger,
        cache_logger_on_first_use=True,
    )

    def make_formatter(render: Any) -> structlog.stdlib.ProcessorFormatter:
        return structlog.stdlib.ProcessorFormatter(
            foreign_pre_chain=_shared_processors,
            processors=[
                structlog.stdlib.ProcessorFormatter.remove_processors_meta,
                *render,
            ],
        )

    console_render: list[Any] = (
        [structlog.processors.format_exc_info, structlog.processors.JSONRenderer()]
        if use_json
        else [structlog.dev.ConsoleRenderer(colors=True)]
    )

    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setFormatter(make_formatter(console_render))
    handlers: list[logging.Handler] = [console_handler]

    if not use_json:
        dm.create_directory(dm.log_dir)
        file_formatter = make_formatter(
            [structlog.processors.format_exc_info, structlog.processors.JSONRenderer()]
        )
        for filename, level in (
            ("info.log", logging.INFO),
            ("errors.log", logging.ERROR),
        ):
            file_handler = MyTimedRotatingFileHandler(
                filename=str(dm.log_dir / filename),
                when="midnight",
                encoding="utf8",
                delay=True,
            )
            file_handler.setLevel(level)
            file_handler.setFormatter(file_formatter)
            handlers.append(file_handler)

    root = logging.getLogger()
    root.handlers = handlers
    root.setLevel(logging.INFO if use_json else logging.DEBUG)


# Structured fields go as kwargs, not stdlib extra={...}.
setup_logging()
logger: structlog.stdlib.BoundLogger = structlog.stdlib.get_logger(
    common_settings.ENVIRONMENT
)
