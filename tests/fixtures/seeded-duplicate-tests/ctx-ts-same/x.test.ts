import { describe, expect, it, vi, test } from 'vitest';
import { svc } from './a';

it('runs', () => {
    expect(svc.run(1)).toBe(2);
    expect(svc.run(2)).toBe(4);
});
