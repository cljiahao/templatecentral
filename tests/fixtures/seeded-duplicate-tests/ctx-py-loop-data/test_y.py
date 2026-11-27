from lib import svc

TABLE = [3, 4]

for row in TABLE:

    def test_runs():
        assert svc.run(1) == 2
        assert svc.run(2) == 4
