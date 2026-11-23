"""Module docstring with a # hash and (aside)."""
URL = "https://example.com/#fragment"
RAW = r"# not a comment"
TEXT = """
# still a string (with an aside)
"""
FSTR = f"{URL} # not a comment"


# Greets by name.
def greet(name):
    """Long docstring with a # hash.

    Holds (an aside) and more
    lines than the comment limit allows.
    Fourth docstring line.
    """
    return "# " + name
