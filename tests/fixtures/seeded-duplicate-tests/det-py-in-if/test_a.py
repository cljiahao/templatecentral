import sys
from lib import compute

if sys.platform:

    def test_one():
        assert compute(1) == 2
        assert compute(2) == 4

    def test_two():
        assert compute(1) == 2
        assert compute(2) == 4
