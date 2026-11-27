from lib import compute


class TestA:
    def test_one(self):
        r = compute(4, 5)
        assert r.total == 9


class TestB:
    def test_two(self):
        r = compute(4, 5)
        assert r.total == 9
