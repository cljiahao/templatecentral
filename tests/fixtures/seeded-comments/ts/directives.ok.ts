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

declare const make: () => number;
declare const name: string;
export const p = /*#__PURE__*/ make();
export const q = /* @__PURE__ */ make();
export const lazy = import(/* webpackChunkName: "chunk", webpackPrefetch: true */ './x');
export const dyn = import(/* @vite-ignore */ name);
export const key = 'abc'; // gitleaks:allow
/* biome-ignore lint/suspicious/noExplicitAny: legacy shape */
// prettier-ignore
export const matrix = [1, 0, 0, 1];
