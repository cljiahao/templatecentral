import { describe, expect, it } from 'vitest';
import { makeA, makeB } from './lib';

describe('suite', () => {
  const svc = makeA();
  it('runs', () => {
    expect(svc.run(1)).toBe(2);
    expect(svc.run(2)).toBe(4);
  });
});
