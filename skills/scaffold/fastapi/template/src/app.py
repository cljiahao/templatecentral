import ipaddress
import textwrap

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from api.routes import router
from core.config import api_settings, common_settings
from core.security_headers import SECURITY_HEADERS
from error_handler import configure_exceptions


class SecurityHeadersMiddleware:
    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        async def _send(message: Message) -> None:
            if message["type"] == "http.response.start":
                headers = list(message.get("headers", []))
                headers.extend(SECURITY_HEADERS)
                message = {**message, "headers": headers}
            await send(message)

        await self.app(scope, receive, _send)


class ForwardedHostMiddleware:
    """Rewrites the Host header from X-Forwarded-Host so request.base_url reflects the public hostname.

    uvicorn's ProxyHeadersMiddleware handles X-Forwarded-Proto and X-Forwarded-For but not
    X-Forwarded-Host. Starlette builds request.url/base_url from the Host header (scope['server']
    is only a fallback when Host is absent), so the Host header itself is what must change.

    Trust model: only mounted when TRUST_PROXY is set (see configure_proxy_headers), and added
    AFTER ProxyHeadersMiddleware so it runs outermost — scope['client'] is still the direct peer
    (the proxy), validated against TRUST_PROXY before the header is honored. Without this guard
    any client reaching the app directly could spoof generated URLs (e.g. password-reset links).
    """

    def __init__(self, app: ASGIApp, trusted: str = "*") -> None:
        self.app = app
        self.trust_all = trusted.strip() == "*"
        self.trusted_networks = (
            []
            if self.trust_all
            else [
                ipaddress.ip_network(t.strip(), strict=False)
                for t in trusted.split(",")
                if t.strip()
            ]
        )

    def _peer_is_trusted(self, scope: Scope) -> bool:
        if self.trust_all:
            return True
        client = scope.get("client")
        if not client:
            return False
        try:
            peer = ipaddress.ip_address(client[0])
        except ValueError:
            return False
        return any(peer in net for net in self.trusted_networks)

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] in ("http", "websocket") and self._peer_is_trusted(scope):
            forwarded = next(
                (v for k, v in scope["headers"] if k == b"x-forwarded-host"), None
            )
            host = forwarded.split(b",")[0].strip() if forwarded else b""
            if host:
                headers = [(k, v) for k, v in scope["headers"] if k != b"host"]
                scope = {**scope, "headers": [*headers, (b"host", host)]}
        await self.app(scope, receive, send)


def configure_cors(app: FastAPI) -> None:
    """Configures Cross-Origin Resource Sharing (CORS) middleware for the FastAPI application.

    Args:
        app: The FastAPI application instance.
    """
    origins = api_settings.ALLOWED_CORS

    app.add_middleware(
        CORSMiddleware,
        allow_origins=origins,
        allow_credentials=True,
        allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
        allow_headers=["Content-Type", "Authorization"],
    )


def configure_security_headers(app: FastAPI) -> None:
    app.add_middleware(SecurityHeadersMiddleware)


def configure_proxy_headers(app: FastAPI) -> None:
    """Enables reverse-proxy header trust when TRUST_PROXY is set.

    Safe to omit (empty TRUST_PROXY) for local dev or non-proxy deployments. uvicorn takes
    comma-separated IPs/CIDRs, not a hop count: it walks X-Forwarded-For right-to-left and
    returns the first address NOT in TRUST_PROXY as the client.
    One-hop (ALB → App): set TRUST_PROXY to the ALB's VPC CIDR (e.g. 10.0.0.0/8).
    Two-hop (ALB → Traefik → App): TRUST_PROXY must cover BOTH Traefik's container CIDR and
    the ALB's CIDR (comma-separated, or one VPC CIDR spanning both) — trusting Traefik alone
    resolves every client to the ALB's IP. Traefik must also keep the ALB's X-Forwarded-For
    (entryPoints forwardedHeaders.trustedIPs = ALB CIDR).
    Use * only in closed networks — it takes the leftmost, client-supplied X-Forwarded-For entry.
    """
    if not api_settings.TRUST_PROXY:
        return
    from uvicorn.middleware.proxy_headers import ProxyHeadersMiddleware

    # Order matters: the last middleware added runs outermost. ForwardedHostMiddleware must run
    # BEFORE ProxyHeadersMiddleware rewrites scope['client'], so it can validate the direct peer.
    app.add_middleware(ProxyHeadersMiddleware, trusted_hosts=api_settings.TRUST_PROXY)
    app.add_middleware(ForwardedHostMiddleware, trusted=api_settings.TRUST_PROXY)


def start_application() -> FastAPI:
    """Initialize and configures the FastAPI application.

    Returns:
        The initialized and configured FastAPI application instance.
    """
    # Setting openapi_url=None also auto-disables docs_url/redoc_url — set all three
    # explicitly so the intent reads clearly at the call site. Schema/docs disclosure in
    # prod is an unnecessary attack-surface/information-disclosure risk.
    is_dev = common_settings.ENVIRONMENT == "dev"
    app = FastAPI(
        title=common_settings.PROJECT_NAME,
        version=common_settings.PROJECT_VERSION,
        description=textwrap.dedent(common_settings.PROJECT_DESCRIPTION),
        root_path=f"/{api_settings.FASTAPI_ROOT}" if api_settings.FASTAPI_ROOT else "",
        docs_url="/docs" if is_dev else None,
        redoc_url="/redoc" if is_dev else None,
        openapi_url="/openapi.json" if is_dev else None,
        swagger_ui_parameters={
            "defaultModelsExpandDepth": -1,
            "docExpansion": "none",
        },
    )

    # Last added runs outermost: security headers wrap CORS so preflight responses get them too.
    configure_cors(app)
    configure_security_headers(app)
    configure_proxy_headers(app)
    configure_exceptions(app)
    app.include_router(router)

    return app


app = start_application()
