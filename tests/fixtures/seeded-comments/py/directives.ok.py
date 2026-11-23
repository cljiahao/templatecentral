#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# Copyright (c) Example. All rights reserved.
# Licensed under the MIT License.
# Third licence line.
# Fourth licence line.
import os  # noqa: F401

x: int = "a"  # type: ignore[assignment]


# Returns one.
def f():
    # pylint: disable=unused-variable
    return 1  # pragma: no cover


# Returns two.
def two():
    y = 2  # nosec B101
    # fmt: off
    z = [1,  2]
    # fmt: on
    w = 3  # isort: skip
    v = 4  # pyright: ignore[reportGeneralTypeIssues]
    u = "k"  # gitleaks:allow
    t = 5  # pylint: disable=unused-variable
    return y, z, w, v, u, t


# mypy: ignore-errors
S = 1
