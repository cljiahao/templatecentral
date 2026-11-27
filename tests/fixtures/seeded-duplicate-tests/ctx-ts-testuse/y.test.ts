import { describe, expect, test } from 'vitest';
import { svc } from './lib';
describe('s', () => {
  test.use({ locale: 'fr' });
  test('runs', () => {
    expect(svc.run(1)).toBe(2);
    expect(svc.run(2)).toBe(4);
  });
});
