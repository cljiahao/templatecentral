"""Tests for the JWT/password helpers and the bearer guard."""

from datetime import timedelta

import jwt
import pytest
from fastapi.testclient import TestClient

from core.security import (
    create_access_token,
    decode_access_token,
    hash_password,
    verify_password,
)


@pytest.mark.unit
def test_token_round_trips_subject() -> None:
    """A freshly issued token decodes back to its subject."""
    assert decode_access_token(create_access_token("user-1")) == "user-1"


@pytest.mark.unit
def test_expired_token_is_rejected() -> None:
    """A token past its exp claim decodes to None."""
    token = create_access_token("user-1", expires_delta=timedelta(seconds=-1))
    assert decode_access_token(token) is None


@pytest.mark.unit
def test_unsigned_token_is_rejected() -> None:
    """An alg=none token is rejected by the pinned algorithm list."""
    token = jwt.encode({"sub": "user-1", "exp": 4102444800}, "", algorithm="none")
    assert decode_access_token(token) is None


@pytest.mark.unit
def test_password_hash_verifies_only_the_original() -> None:
    """verify_password accepts the hashed password and nothing else."""
    hashed = hash_password("correct-horse-battery")
    assert verify_password("correct-horse-battery", hashed)
    assert not verify_password("wrong-horse-battery", hashed)


@pytest.mark.unit
def test_me_requires_bearer_token(client: TestClient) -> None:
    """GET /auth/me without a token is 401."""
    assert client.get("/auth/me").status_code == 401
