from a import f


def test_runs():
    result = f()
    assert result.total == 3
    assert len(result.items) == 2
