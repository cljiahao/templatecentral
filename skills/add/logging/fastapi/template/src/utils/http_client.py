# src/utils/http_client.py
import time
from urllib.parse import urlparse, urlunparse

import httpx

from core.logging import logger


def _sanitize_url(url: str) -> str:
    """Drop userinfo, query, and fragment — any of them can carry credentials or tokens."""
    parsed = urlparse(url)
    netloc = parsed.hostname or ""
    if parsed.port:
        netloc += f":{parsed.port}"
    return urlunparse(parsed._replace(netloc=netloc, query="", fragment=""))


async def http_get(url: str, **kwargs) -> httpx.Response:
    safe_url = _sanitize_url(url)
    start = time.monotonic()
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(url, **kwargs)
        duration_ms = round((time.monotonic() - start) * 1000)
        logger.info(
            "Outbound HTTP",
            method="GET",
            url=safe_url,
            status_code=response.status_code,
            duration_ms=duration_ms,
        )
        return response
    except Exception as exc:
        duration_ms = round((time.monotonic() - start) * 1000)
        # Exception type only — httpx messages embed the full, unsanitized request URL.
        logger.error(
            "Outbound HTTP error",
            method="GET",
            url=safe_url,
            duration_ms=duration_ms,
            error_type=type(exc).__name__,
        )
        raise
