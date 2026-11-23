from unittest.mock import patch


@patch('a.x')
class TestA:
    def test_runs(self, mock_x):
        assert mock_x.run(1) == 2
        assert mock_x.run(2) == 4


@patch('b.x')
class TestB:
    def test_runs(self, mock_x):
        assert mock_x.run(1) == 2
        assert mock_x.run(2) == 4
