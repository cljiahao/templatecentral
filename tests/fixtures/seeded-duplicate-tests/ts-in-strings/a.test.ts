import { expect, it } from 'vitest';
import { render } from './lib';

const sample = "it('x', () => { const r = compute(1, 2); expect(r.total).toBe(3); expect(r.items.length).toBe(2); })";
const sampleAgain = "it('y', () => { const r = compute(1, 2); expect(r.total).toBe(3); expect(r.items.length).toBe(2); })";
const tpl = `
it('z', () => { const r = compute(1, 2); expect(r.total).toBe(3); expect(r.items.length).toBe(2); });
it('w', () => { const r = compute(1, 2); expect(r.total).toBe(3); expect(r.items.length).toBe(2); });
`;
// it('c', () => { const r = compute(1, 2); expect(r.total).toBe(3); expect(r.items.length).toBe(2); });
// it('d', () => { const r = compute(1, 2); expect(r.total).toBe(3); expect(r.items.length).toBe(2); });

it('renders the samples', () => {
  expect(render(sample, sampleAgain, tpl)).toContain('x');
});
