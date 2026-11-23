import { expect, it } from 'vitest';
import { svc } from './lib';
const tableA = [1, 2];
const tableB = [3, 4];
for (const t of tableB) {
  it('runs', () => {
    expect(svc.run(t)).toBe(2);
    expect(svc.run(t + 1)).toBe(4);
  });
}
