"""Cookie mode: session cookie attributes, CSRF on unsafe methods, Bearer fallback."""

from typing import Annotated

import pytest
from fastapi import Depends, FastAPI, Response
from fastapi.testclient import TestClient

from api.dependencies.auth import get_current_user, set_session_cookies
from core.security import (
    COOKIE_SECURE,
    CSRF_COOKIE,
    CSRF_HEADER,
    SESSION_COOKIE,
    create_access_token,
)

probe = FastAPI()
User = Annotated[str, Depends(get_current_user)]


@probe.post("/login", status_code=204)
def _login(response: Response, sub: str = "user-1") -> None:
    set_session_cookies(response, create_access_token(sub))


@probe.get("/me")
def _me(user_id: User) -> dict[str, str]:
    return {"id": user_id}


@probe.post("/write")
def _write(user_id: User) -> dict[str, str]:
    return {"id": user_id}


@pytest.fixture
def browser() -> TestClient:
    # https so the cookie jar returns Secure cookies when COOKIE_SECURE is on (non-dev).
    client = TestClient(probe, base_url="https://testserver")
    assert client.post("/login").status_code == 204
    return client


@pytest.mark.unit
def test_login_sets_hardened_cookies() -> None:
    res = TestClient(probe, base_url="https://testserver").post("/login")
    headers = res.headers.get_list("set-cookie")
    session = next(h for h in headers if h.startswith(f"{SESSION_COOKIE}="))
    csrf = next(h for h in headers if h.startswith(f"{CSRF_COOKIE}="))
    assert "HttpOnly" in session
    assert "HttpOnly" not in csrf
    for cookie in (session, csrf):
        assert "SameSite=strict" in cookie
        assert "Path=/" in cookie
        assert ("Secure" in cookie) == COOKIE_SECURE


@pytest.mark.unit
def test_cookie_authenticates_safe_requests(browser: TestClient) -> None:
    assert browser.get("/me").json() == {"id": "user-1"}


@pytest.mark.unit
def test_unsafe_request_needs_csrf_header(browser: TestClient) -> None:
    assert browser.post("/write").status_code == 403
    assert (
        browser.post("/write", headers={CSRF_HEADER: "forged.token"}).status_code == 403
    )
    token = browser.cookies[CSRF_COOKIE]
    assert browser.post("/write", headers={CSRF_HEADER: token}).status_code == 200


@pytest.mark.unit
def test_csrf_token_is_bound_to_its_session(browser: TestClient) -> None:
    """A valid token from one session is rejected under another (cookie injection)."""
    stolen = browser.cookies[CSRF_COOKIE]
    other = TestClient(probe, base_url="https://testserver")
    other.post("/login?sub=user-2")
    other.cookies.set(CSRF_COOKIE, stolen)
    assert other.post("/write", headers={CSRF_HEADER: stolen}).status_code == 403


@pytest.mark.unit
def test_bearer_needs_no_csrf() -> None:
    headers = {"Authorization": f"Bearer {create_access_token('user-2')}"}
    assert TestClient(probe).post("/write", headers=headers).json() == {"id": "user-2"}


@pytest.mark.unit
def test_no_credentials_is_401() -> None:
    assert TestClient(probe).get("/me").status_code == 401


@pytest.mark.unit
def test_logout_clears_cookies(client: TestClient) -> None:
    res = client.post("/auth/logout")
    assert res.status_code == 204
    cleared = res.headers.get_list("set-cookie")
    assert any(h.startswith(f"{SESSION_COOKIE}=") and "Max-Age=0" in h for h in cleared)
    assert any(h.startswith(f"{CSRF_COOKIE}=") and "Max-Age=0" in h for h in cleared)


@pytest.mark.unit
@pytest.mark.parametrize("headers", [{}, {"Content-Type": "text/plain"}])
def test_session_login_requires_json(
    client: TestClient, headers: dict[str, str]
) -> None:
    """No Content-Type or text/plain (CORS-simple: no preflight) is refused before login."""
    body = b'{"email": "a@example.com", "password": "correct-horse-battery"}'
    res = client.post("/auth/session", content=body, headers=headers)
    assert res.status_code == 415
