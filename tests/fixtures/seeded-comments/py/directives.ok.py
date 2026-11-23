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
