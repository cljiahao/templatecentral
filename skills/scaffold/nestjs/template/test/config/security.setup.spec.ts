import { describe, expect, it } from 'vitest';
import { portalFrameAncestor } from '../../src/config/setups/security.setup';

describe('portalFrameAncestor', () => {
  it('accepts a single https portal origin', () => {
    expect(portalFrameAncestor('https://appcentral-uat.cpfnet.gov.sg')).toBe(
      'https://appcentral-uat.cpfnet.gov.sg'
    );
  });

  it.each([
    undefined,
    '',
    '*',
    'http://appcentral.example.gov.sg',
    'https://*.example.gov.sg',
    'https://example.gov.sg:8443',
    'https://example.gov.sg/path',
    'https://Example.gov.sg',
    'https://localhost',
    "https://example.gov.sg; script-src 'unsafe-inline'",
    'https://example.gov.sg\nX-Injected: 1',
  ])('falls back to deny for %s', (origin) => {
    expect(portalFrameAncestor(origin)).toBeNull();
  });
});
