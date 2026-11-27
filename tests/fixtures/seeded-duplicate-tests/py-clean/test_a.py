import pytest
from lib import compute


def test_sums():
    r = compute(1, 2)
    assert r.total == 3
    assert len(r.items) == 2


def test_rejects_negatives():
    with pytest.raises(ValueError):
        compute(-1, 2)


class TestProduct:
    def test_multiplies(self):
        r = compute(3, 4, mode="product")
        assert r.total == 12
        assert r.items == [3, 4]
