def test_runs(svc):
    assert svc.run(1) == 2
    assert svc.run(2) == 4
