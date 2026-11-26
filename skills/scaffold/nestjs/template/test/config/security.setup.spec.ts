import { expect, it } from 'vitest';
import { portalFrameAncestor } from '../../src/config/setups/security.setup';

const portal = 'https://portal.example.com';

it.each([
  [portal, portal],
  [undefined, null],
  ['*', null],
  ['http://portal.example.gov.sg', null],
  ['https://*.example.gov.sg', null],
  ['https://example.gov.sg:8443', null],
  ['https://example.gov.sg/path', null],
  ['https://Example.gov.sg', null],
  ['https://localhost', null],
  ["https://example.gov.sg; script-src 'unsafe-inline'", null],
  ['https://example.gov.sg\nX-Injected: 1', null],
])('maps %j to %j (only a single https origin is allowed)', (origin, expected) => {
  expect(portalFrameAncestor(origin)).toBe(expected);
});
