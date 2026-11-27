SAMPLE = """
def test_x():
    r = compute(1, 2)
    assert r.total == 3
    assert len(r.items) == 2
    assert r.ok is True


def test_y():
    r = compute(1, 2)
    assert r.total == 3
    assert len(r.items) == 2
    assert r.ok is True
"""

# def test_c():
#     r = compute(1, 2)
#     assert r.total == 3


def test_renders():
    assert "test_x" in SAMPLE
