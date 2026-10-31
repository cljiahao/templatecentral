"""Deny-by-default role and ownership checks."""

from collections.abc import Generator
from typing import Annotated

import pytest
from fastapi import Depends, FastAPI, HTTPException
from fastapi.testclient import TestClient

from api.dependencies.authz import ensure_owner, get_current_roles, require_roles

probe = FastAPI()


@probe.get("/_authz-probe")
def _admin_only(
    user_id: Annotated[str, Depends(require_roles("admin"))],
) -> dict[str, str]:
    return {"id": user_id}


@pytest.fixture
def client() -> Generator[TestClient]:
    """Probe client; shadows the root fixture so no feature route is involved."""
    with TestClient(probe) as client:
        yield client
    probe.dependency_overrides.clear()


@pytest.mark.unit
def test_require_roles_rejects_user_without_role(
    client: TestClient, auth_headers: dict[str, str]
) -> None:
    """The default role lookup grants nothing, so a guarded route is 403."""
    res = client.get("/_authz-probe", headers=auth_headers)
    assert res.status_code == 403
    assert res.json() == {"detail": "Insufficient permissions."}


@pytest.mark.unit
def test_require_roles_allows_user_with_role(
    client: TestClient, auth_headers: dict[str, str]
) -> None:
    """A user holding the required role reaches the handler as themselves."""
    probe.dependency_overrides[get_current_roles] = lambda: frozenset({"admin"})
    res = client.get("/_authz-probe", headers=auth_headers)
    assert res.status_code == 200
    assert res.json() == {"id": "test-user"}


@pytest.mark.unit
def test_require_roles_without_roles_is_a_programming_error() -> None:
    """An empty role list would admit nobody or everybody, so it fails at definition time."""
    with pytest.raises(ValueError, match="at least one role"):
        require_roles()


@pytest.mark.unit
def test_ensure_owner_hides_other_users_record() -> None:
    with pytest.raises(HTTPException) as exc:
        ensure_owner("u2", "u1")
    assert exc.value.status_code == 404


@pytest.mark.unit
def test_ensure_owner_hides_missing_record() -> None:
    with pytest.raises(HTTPException) as exc:
        ensure_owner(None, "u1")
    assert exc.value.status_code == 404


@pytest.mark.unit
def test_ensure_owner_allows_owner() -> None:
    ensure_owner("u1", "u1")
