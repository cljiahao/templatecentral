import pytest
from lib import A, B


@pytest.fixture
def svc():
    return B()


def test_runs(svc):
    assert svc.run(1) == 2
    assert svc.run(2) == 4
