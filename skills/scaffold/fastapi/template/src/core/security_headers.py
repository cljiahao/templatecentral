import re

from core.config import common_settings

# One https origin; fullmatch, not $, since a trailing newline would pass; anything else denies, so no CSP injection.
_PORTAL_ORIGIN_RE = re.compile(r"https://[a-z0-9-]+(\.[a-z0-9-]+)+")


def frame_ancestors(portal_origin: str) -> bytes | None:
    """Return the validated APPCENTRAL_PORTAL_ORIGIN as a frame-ancestors source, else None."""
    if _PORTAL_ORIGIN_RE.fullmatch(portal_origin):
        return portal_origin.encode()
    return None


def _build() -> list[tuple[bytes, bytes]]:
    # Frame protection is skipped in dev so the /docs UI renders in IDE preview panes.
    is_dev = common_settings.ENVIRONMENT == "dev"
    # Only the portal origin may frame the app.
    portal = frame_ancestors(common_settings.APPCENTRAL_PORTAL_ORIGIN)
    headers = [
        (b"strict-transport-security", b"max-age=31536000; includeSubDomains"),
        (b"x-content-type-options", b"nosniff"),
        (b"referrer-policy", b"strict-origin-when-cross-origin"),
        (b"permissions-policy", b"camera=(), microphone=(), geolocation=()"),
        # 0 disables the legacy XSS auditor, itself exploitable.
        (b"x-xss-protection", b"0"),
        # Per-user data must not reach shared caches.
        (b"cache-control", b"no-store"),
        # Outside dev nothing may load: OWASP REST baseline.
        (
            b"content-security-policy",
            b"base-uri 'self'; object-src 'none'"
            if is_dev
            else b"default-src 'none'; frame-ancestors "
            + (portal or b"'none'")
            + b"; base-uri 'none'; form-action 'none'",
        ),
    ]
    # frame-ancestors supersedes X-Frame-Options, sent only when framing is denied.
    if not is_dev and portal is None:
        headers.append((b"x-frame-options", b"DENY"))
    return headers


# Shared with the unhandled-exception handler, which runs outside user middleware.
SECURITY_HEADERS = _build()
