#!/usr/bin/env node
/*
 * Copyright (c) Example. All rights reserved.
 * Licensed under the MIT License.
 * Third licence line.
 * Fourth licence line.
 */
/* eslint-disable no-console -- the banner logs on boot */
// @ts-expect-error legacy shape of the fixture
export const a: number = "x"; // eslint-disable-line no-console -- logs once at startup

// Wraps a call.
export function g() {
  // @ts-ignore stale typings from the vendor
  return 1; // NOSONAR -- reviewed by the owner
}

/* istanbul ignore next -- guarded by the caller */
export const h = 1;

// c8 ignore next -- platform specific branch only
// v8 ignore next -- platform specific branch only
export const i = 2;

declare const make: () => number;
declare const name: string;
export const p = /*#__PURE__*/ make();
export const q = /* @__PURE__ */ make();
export const lazy = import(/* webpackChunkName: "chunk", webpackPrefetch: true */ './x');
export const dyn = import(/* @vite-ignore */ name);
export const key = 'abc'; // gitleaks:allow -- public example key
/* biome-ignore lint/suspicious/noExplicitAny: legacy shape of the data */
// prettier-ignore
export const matrix = [1, 0, 0, 1];
