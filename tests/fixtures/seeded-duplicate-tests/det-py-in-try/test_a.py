from lib import compute

try:

    def test_one():
        assert compute(1) == 2
        assert compute(2) == 4

    def test_two():
        assert compute(1) == 2
        assert compute(2) == 4

except ImportError:
    pass
