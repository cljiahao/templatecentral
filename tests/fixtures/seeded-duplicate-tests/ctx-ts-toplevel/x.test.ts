import { expect, it } from 'vitest';
import { svc } from './lib';
svc.mode = 'a';
it('runs', () => {
    expect(svc.run(1)).toBe(2);
    expect(svc.run(2)).toBe(4);
});
