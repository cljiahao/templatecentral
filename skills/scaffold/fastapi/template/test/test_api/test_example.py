"""Tests for the example endpoint."""

import pytest
from factories.models import create_example_request
from fastapi.testclient import TestClient


@pytest.mark.unit
def test_example_returns_greeting(client: TestClient) -> None:
    """POST /example returns a greeting with the given name."""
    payload = create_example_request(name="Alice")
    response = client.post("/example", json=payload)

    assert response.status_code == 200
    data = response.json()
    assert data["message"] == "Hello, Alice!"
    assert data["items"] == ["Hello, Alice!"]


@pytest.mark.unit
def test_example_repeats(client: TestClient) -> None:
    """POST /example repeats the greeting repeat_count times."""
    payload = create_example_request(name="Bob", repeat_count=3)
    response = client.post("/example", json=payload)

    assert response.status_code == 200
    assert len(response.json()["items"]) == 3


@pytest.mark.unit
def test_example_rejects_invalid_count(client: TestClient) -> None:
    """POST /example rejects repeat_count outside 1-10."""
    payload = create_example_request(repeat_count=99)
    response = client.post("/example", json=payload)

    assert response.status_code == 422
