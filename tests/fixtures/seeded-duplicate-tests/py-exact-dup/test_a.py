from lib import compute


def test_sums_first():
    """Docstring one."""
    r = compute(1, 2)
    assert r.total == 3
    assert len(r.items) == 2


def test_sums_again():
    # same body, other title, a comment, another docstring
    """Docstring two."""
    r = compute(1, 2)
    assert r.total == 3  # trailing
    assert len(r.items) == 2
