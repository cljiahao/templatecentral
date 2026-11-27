from lib import compute


def test_sums_three():
    r = compute(7, 8)
    assert r.total == 15
    assert len(r.items) == 2
    assert r.ok is True
    assert r.label == "sum"
