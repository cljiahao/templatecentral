#!/usr/bin/env node
/*
 * Copyright (c) Example. All rights reserved.
 * Licensed under the MIT License.
 * Third licence line.
 * Fourth licence line.
 */
/* eslint-disable no-console -- the banner logs on boot */
// @ts-expect-error legacy shape
export const a: number = "x"; // eslint-disable-line no-console -- logs once

// Wraps a call.
export function g() {
  // @ts-ignore stale typings
  return 1; // NOSONAR -- reviewed
}

/* istanbul ignore next -- guarded by the caller */
export const h = 1;

// c8 ignore next -- platform branch
// v8 ignore next -- platform branch
export const i = 2;

declare const make: () => number;
declare const name: string;
export const p = /*#__PURE__*/ make();
export const q = /* @__PURE__ */ make();
export const lazy = import(/* webpackChunkName: "chunk", webpackPrefetch: true */ './x');
export const dyn = import(/* @vite-ignore */ name);
export const key = 'abc'; // gitleaks:allow -- public example key
/* biome-ignore lint/suspicious/noExplicitAny: legacy shape */
// prettier-ignore
export const matrix = [1, 0, 0, 1];
