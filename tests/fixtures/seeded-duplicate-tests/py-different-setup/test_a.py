import pytest
from lib import compute


def test_with_cache(cache_on):
    r = compute(1, 2)
    assert r.total == 3
    assert len(r.items) == 2


def test_without_cache(cache_off):
    r = compute(1, 2)
    assert r.total == 3
    assert len(r.items) == 2
