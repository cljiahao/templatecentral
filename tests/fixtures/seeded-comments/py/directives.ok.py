#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# Copyright (c) Example. All rights reserved.
# SPDX-License-Identifier: MIT
import os  # noqa: F401 -- kept for the plugin

x: int = "a"  # type: ignore[assignment]  # legacy shape of the data


# Returns one.
def f():
    # pylint: disable=unused-variable -- kept for tracing
    return 1  # pragma: no cover -- exercised by the e2e run


# Returns two.
def two():
    y = 2  # nosec B101 -- asserts a test invariant
    # fmt: off
    z = [1,  2]
    # fmt: on
    w = 3  # isort: skip
    v = 4  # pyright: ignore[reportGeneralTypeIssues]  # legacy shape of the data
    u = "k"  # gitleaks:allow -- public example key
    t = 5  # pylint: disable=unused-variable -- kept for tracing
    return y, z, w, v, u, t


# mypy: ignore-errors
S = 1
