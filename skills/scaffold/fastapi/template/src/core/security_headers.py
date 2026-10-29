import re

from core.config import common_settings

# Exactly one https origin: lowercase host labels, no path, port, wildcard, quotes,
# whitespace or semicolons. Anything else falls back to deny, so the value can never
# inject extra CSP directives or headers. fullmatch, not $, so a trailing newline fails.
_PORTAL_ORIGIN_RE = re.compile(r"https://[a-z0-9-]+(\.[a-z0-9-]+)+")


def frame_ancestors(portal_origin: str) -> bytes | None:
    """Return the validated APPCENTRAL_PORTAL_ORIGIN as a frame-ancestors source, else None."""
    if _PORTAL_ORIGIN_RE.fullmatch(portal_origin):
        return portal_origin.encode()
    return None


def _build() -> list[tuple[bytes, bytes]]:
    # Anti-clickjacking (X-Frame-Options, CSP frame-ancestors) is skipped in dev — the
    # built-in docs UI at /docs is otherwise blocked from rendering in IDE-embedded preview
    # panes (most render via <iframe>, and browsers enforce these headers even for localhost).
    # Full protection still applies in every deployed environment (prod, uat).
    is_dev = common_settings.ENVIRONMENT == "dev"
    # Only the appCentral portal (APPCENTRAL_PORTAL_ORIGIN, injected at runtime) may frame
    # the app; unset or invalid denies all framing.
    portal = frame_ancestors(common_settings.APPCENTRAL_PORTAL_ORIGIN)
    headers = [
        (b"strict-transport-security", b"max-age=31536000; includeSubDomains"),
        (b"x-content-type-options", b"nosniff"),
        (b"referrer-policy", b"strict-origin-when-cross-origin"),
        (b"permissions-policy", b"camera=(), microphone=(), geolocation=()"),
        # "0" disables the legacy XSS auditor, itself exploitable in older browsers.
        (b"x-xss-protection", b"0"),
        # API responses carry per-user data; never let shared caches store them.
        (b"cache-control", b"no-store"),
        # JSON-only API outside dev (docs are dev-only), so nothing may load: OWASP REST
        # baseline. Dev stays loose enough for the /docs UI.
        (
            b"content-security-policy",
            b"base-uri 'self'; object-src 'none'"
            if is_dev
            else b"default-src 'none'; frame-ancestors "
            + (portal or b"'none'")
            + b"; base-uri 'none'; form-action 'none'",
        ),
    ]
    # X-Frame-Options cannot express a single allowed origin; frame-ancestors supersedes
    # it, so it is sent only when framing is denied outright.
    if not is_dev and portal is None:
        headers.append((b"x-frame-options", b"DENY"))
    return headers


# Shared by SecurityHeadersMiddleware and the unhandled-exception handler: Starlette runs
# that handler in ServerErrorMiddleware, outside every user middleware.
SECURITY_HEADERS = _build()
