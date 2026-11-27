from lib import compute


def test_sums_one():
    r = compute(1, 2)
    assert r.total == 3
    assert len(r.items) == 2
    assert r.ok is True
    assert r.label == "sum"


def test_sums_two():
    r = compute(10, 20)
    assert r.total == 30
    assert len(r.items) == 2
    assert r.ok is True
    assert r.label == "sum"
