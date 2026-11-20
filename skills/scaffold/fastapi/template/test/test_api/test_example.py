import pytest
from factories.models import create_example_request
from fastapi.testclient import TestClient


def test_example_greets_and_repeats(client: TestClient) -> None:
    payload = create_example_request(name="Alice", repeat_count=3)
    response = client.post("/example", json=payload)

    assert response.status_code == 200
    data = response.json()
    assert data["message"] == "Hello, Alice!"
    assert data["items"] == ["Hello, Alice!"] * 3


@pytest.mark.parametrize(
    "repeat_count", [0, 11, 99], ids=["below-min", "above-max", "far-above"]
)
def test_example_rejects_out_of_range_count(
    client: TestClient, repeat_count: int
) -> None:
    response = client.post(
        "/example", json=create_example_request(repeat_count=repeat_count)
    )

    assert response.status_code == 422
