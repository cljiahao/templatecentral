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
    """Rewrites Host from X-Forwarded-Host so request.base_url reflects the public hostname."""

    # Honored only from TRUST_PROXY peers; otherwise a direct client could spoof generated URLs such as reset links.

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
    """Adds the CORS middleware."""
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
    """Trusts reverse-proxy headers when TRUST_PROXY is set."""
    # TRUST_PROXY takes IPs/CIDRs, not a hop count: list every proxy hop and have an inner proxy keep the outer X-Forwarded-For, or all clients resolve to the nearest proxy; * lets a client-supplied X-Forwarded-For win.
    if not api_settings.TRUST_PROXY:
        return
    from uvicorn.middleware.proxy_headers import ProxyHeadersMiddleware

    # Last added runs outermost, so ForwardedHostMiddleware sees the request before ProxyHeadersMiddleware rewrites the client.
    app.add_middleware(ProxyHeadersMiddleware, trusted_hosts=api_settings.TRUST_PROXY)
    app.add_middleware(ForwardedHostMiddleware, trusted=api_settings.TRUST_PROXY)


def start_application() -> FastAPI:
    """Builds the configured FastAPI application."""
    # Docs are dev-only: openapi_url=None already disables the docs routes; all three are set explicitly.
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

    # Security headers wrap CORS so preflight responses get them.
    configure_cors(app)
    configure_security_headers(app)
    configure_proxy_headers(app)
    configure_exceptions(app)
    app.include_router(router)

    return app


app = start_application()
