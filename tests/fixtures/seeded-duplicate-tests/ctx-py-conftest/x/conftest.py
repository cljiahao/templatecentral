import pytest
from lib import A, B


@pytest.fixture
def svc():
    return A()
