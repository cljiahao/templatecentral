import pytest

from core.security_headers import frame_ancestors


def test_frame_ancestors_accepts_portal_origin() -> None:
    origin = "https://appcentral-uat.cpfnet.gov.sg"
    assert frame_ancestors(origin) == origin.encode()


@pytest.mark.parametrize(
    "origin",
    [
        "",
        "*",
        "http://appcentral.example.gov.sg",
        "https://*.example.gov.sg",
        "https://example.gov.sg:8443",
        "https://example.gov.sg/path",
        "https://Example.gov.sg",
        "https://localhost",
        "https://example.gov.sg; script-src 'unsafe-inline'",
        "https://example.gov.sg\n",
        "https://example.gov.sg\r\nX-Injected: 1",
    ],
)
def test_frame_ancestors_rejects_invalid_origin(origin: str) -> None:
    assert frame_ancestors(origin) is None
