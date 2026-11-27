from lib import A, B


class TestA:
    svc = A()

    def test_runs(self):
        assert self.svc.run(1) == 2
        assert self.svc.run(2) == 4


class TestB:
    svc = B()

    def test_runs(self):
        assert self.svc.run(1) == 2
        assert self.svc.run(2) == 4
