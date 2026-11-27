import { expect, it, vi } from 'vitest';
import { svc } from './lib';
vi.mock('./a');
it('runs', () => {
    expect(svc.run(1)).toBe(2);
    expect(svc.run(2)).toBe(4);
});
