class InvalidInputError(Exception):
    """Raised when user input fails domain validation as 400."""


class NoResultsFoundError(Exception):
    """Raised when a lookup yields no results as 404."""
