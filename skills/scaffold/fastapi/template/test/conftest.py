"""Root conftest — shared fixtures available to all tests."""

from collections.abc import Generator

import pytest
from fastapi.testclient import TestClient

from app import app


@pytest.fixture
def client() -> Generator[TestClient]:
    """FastAPI test client."""
    with TestClient(app) as client:
        yield client
