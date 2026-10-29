from datetime import date


def year_month_to_date(year_month: str) -> date:
    """Convert 'YYYY-MM' string to a date (first of month)."""
    year, month = year_month.split("-")
    return date(int(year), int(month), 1)


def date_to_year_month(d: date) -> str:
    """Convert a date to 'YYYY-MM' string."""
    return d.strftime("%Y-%m")
