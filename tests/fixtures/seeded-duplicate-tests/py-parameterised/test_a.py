import pytest
from lib import compute


@pytest.mark.parametrize("a,b,total", [(1, 2, 3)])
def test_one(a, b, total):
    r = compute(a, b)
    assert r.total == total
    assert len(r.items) == 2
    assert r.ok is True


@pytest.mark.parametrize("a,b,total", [(1, 2, 3)])
def test_two(a, b, total):
    r = compute(a, b)
    assert r.total == total
    assert len(r.items) == 2
    assert r.ok is True


@pytest.mark.parametrize("a,b,total", [(1, 2, 3)])
def test_three(a, b, total):
    r = compute(a, b)
    assert r.total == total
    assert len(r.items) == 2
    assert r.ok is True
