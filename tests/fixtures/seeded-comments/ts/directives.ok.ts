#!/usr/bin/env node
/*
 * Copyright (c) Example. All rights reserved.
 * Licensed under the MIT License.
 * Third licence line.
 * Fourth licence line.
 */
/* eslint-disable no-console */
// @ts-expect-error legacy shape
export const a: number = "x"; // eslint-disable-line no-console

// Wraps a call.
export function g() {
  // @ts-ignore
  return 1; // NOSONAR
}

/* istanbul ignore next */
export const h = 1;

// c8 ignore next
// v8 ignore next
export const i = 2;
