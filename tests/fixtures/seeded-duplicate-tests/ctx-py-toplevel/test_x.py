from lib import svc

svc.mode = 'a'


def test_runs():
    assert svc.run(1) == 2
    assert svc.run(2) == 4
