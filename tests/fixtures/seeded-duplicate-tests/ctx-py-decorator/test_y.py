import pytest
from lib import svc


@pytest.mark.usefixtures('two')
def test_runs():
    assert svc.run(1) == 2
    assert svc.run(2) == 4
