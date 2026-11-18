from fastapi.testclient import TestClient


def test_home_returns_welcome(client: TestClient) -> None:
    response = client.get("/")
    assert response.status_code == 200
    assert "msg" in response.json()


def test_health_returns_ok(client: TestClient) -> None:
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "OK"}
