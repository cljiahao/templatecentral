import sys

ITEMS = [
    # Item one.
    1,
]
print(
    # First argument.
    1,
    # Keyword argument.
    sep="",
)
if sys.argv:
    A = 1
# Explains the elif branch.
elif sys.platform:
    A = 2
# Explains the else branch.
else:
    A = 3
try:
    B = 1
# Explains the finally block.
finally:
    C = 2
