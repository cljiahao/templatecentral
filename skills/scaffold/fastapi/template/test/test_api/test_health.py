"""Tests for health and home endpoints."""

import pytest
from fastapi.testclient import TestClient


@pytest.mark.unit
def test_home_returns_welcome(client: TestClient) -> None:
    """GET / returns a welcome message."""
    response = client.get("/")
    assert response.status_code == 200
    assert "msg" in response.json()


@pytest.mark.unit
def test_health_returns_ok(client: TestClient) -> None:
    """GET /health returns OK status."""
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "OK"}
