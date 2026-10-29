import { describe, expect, it } from 'vitest';
import { ExampleService } from './example-service';

describe('ExampleService', () => {
  it('returns all example items', () => {
    const items = ExampleService.getAll();
    expect(items).toHaveLength(3);
    expect(items[0]).toHaveProperty('id');
    expect(items[0]).toHaveProperty('title');
  });

  it('returns a copy, not the original array', () => {
    const a = ExampleService.getAll();
    const b = ExampleService.getAll();
    expect(a).not.toBe(b);
    expect(a).toEqual(b);
  });

  it('finds an item by id', () => {
    const item = ExampleService.getById('item-1');
    expect(item).toBeDefined();
    expect(item?.title).toBe('First item');
  });

  it('returns undefined for unknown id', () => {
    const item = ExampleService.getById('nonexistent');
    expect(item).toBeUndefined();
  });
});
