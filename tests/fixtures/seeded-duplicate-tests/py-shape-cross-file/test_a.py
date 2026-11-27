from lib import compute


def test_sums_one():
    r = compute(1, 2)
    assert r.total == 3
    assert len(r.items) == 2
    assert r.ok is True
    assert r.label == "sum"
