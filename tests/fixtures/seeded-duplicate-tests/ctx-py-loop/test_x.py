from lib import svc

TABLE_A = [1, 2]
TABLE_B = [3, 4]

for row in TABLE_A:

    def test_runs():
        assert svc.run(1) == 2
        assert svc.run(2) == 4
