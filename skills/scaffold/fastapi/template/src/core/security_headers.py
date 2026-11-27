import re

from core.config import common_settings

# One https origin; fullmatch, not $, since a trailing newline would pass; anything else denies, so no CSP injection.
_PORTAL_ORIGIN_RE = re.compile(r"https://[a-z0-9-]+(\.[a-z0-9-]+)+")


def frame_ancestors(portal_origin: str) -> bytes | None:
    """Return the validated EMBED_PARENT_ORIGIN as a frame-ancestors source, else None."""
    if _PORTAL_ORIGIN_RE.fullmatch(portal_origin):
        return portal_origin.encode()
    return None


# Frame protection is skipped in dev for IDE previews; only the portal origin may frame; no shared caching of user data.
def _build() -> list[tuple[bytes, bytes]]:
    is_dev = common_settings.ENVIRONMENT == "dev"
    portal = frame_ancestors(common_settings.EMBED_PARENT_ORIGIN)
    headers = [
        (b"strict-transport-security", b"max-age=31536000; includeSubDomains"),
        (b"x-content-type-options", b"nosniff"),
        (b"referrer-policy", b"strict-origin-when-cross-origin"),
        (b"permissions-policy", b"camera=(), microphone=(), geolocation=()"),
        (b"x-xss-protection", b"0"),
        (b"cache-control", b"no-store"),
        (
            b"content-security-policy",
            b"base-uri 'self'; object-src 'none'"
            if is_dev
            else b"default-src 'none'; frame-ancestors "
            + (portal or b"'none'")
            + b"; base-uri 'none'; form-action 'none'",
        ),
    ]
    if not is_dev and portal is None:
        headers.append((b"x-frame-options", b"DENY"))
    return headers


# Shared with the unhandled-exception handler, which runs outside user middleware.
SECURITY_HEADERS = _build()
