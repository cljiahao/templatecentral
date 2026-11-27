import unittest
from lib import A, B


class Checks(unittest.TestCase):
    def setUp(self):
        self.svc = B()

    def test_runs(self):
        self.assertEqual(self.svc.run(1), 2)
        self.assertEqual(self.svc.run(2), 4)
