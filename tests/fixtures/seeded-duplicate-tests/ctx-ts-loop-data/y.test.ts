import { expect, it } from 'vitest';
import { svc } from './lib';
const table = [3, 4];
for (const t of table) {
  it('runs', () => {
    expect(svc.run(t)).toBe(2);
    expect(svc.run(t + 1)).toBe(4);
  });
}
