from datetime import date

from models.base import BaseImmutableModel, BaseModel
from utils.date import date_to_year_month, year_month_to_date


def test_year_month_round_trips() -> None:
    assert year_month_to_date("2026-03") == date(2026, 3, 1)
    assert date_to_year_month(date(2026, 3, 17)) == "2026-03"


def test_domain_model_bases_are_slotted_dataclasses() -> None:
    assert not hasattr(BaseModel(), "__dict__")
    assert BaseImmutableModel.__dataclass_params__.frozen
