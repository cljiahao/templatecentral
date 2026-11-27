import unittest
from lib import compute


class Checks(unittest.TestCase):
    def test_one(self):
        assert compute(1) == 2
        assert compute(2) == 4

    def test_two(self):
        assert compute(1) == 2
        assert compute(2) == 4
