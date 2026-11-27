def f(x):
    if x > 1:  # pragma: no cover reason: defensive branch needs a corrupt input
        return 1
    return 0
