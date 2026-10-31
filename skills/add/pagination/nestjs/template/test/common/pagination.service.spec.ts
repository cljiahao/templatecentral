// test/common/pagination.service.spec.ts
import { BadRequestException } from '@nestjs/common';
import { describe, expect, it } from 'vitest';
import { PaginationService } from '../../src/common/services/pagination.service';

describe('PaginationService', () => {
  const service = new PaginationService();

  it('computes offset and hasMore', () => {
    expect(service.calculateOffset(3, 10)).toBe(20);
    expect(service.createMetadata(2, 10, 25).hasMore).toBe(true);
    expect(service.createMetadata(3, 10, 25).hasMore).toBe(false);
  });

  it('parses an allowed sort, splitting on the first underscore', () => {
    expect(service.parseSortParam('desc_created_at', ['created_at'])).toEqual({
      field: 'created_at',
      direction: 'desc',
    });
    expect(service.parseSortParam(undefined, ['name'])).toBeNull();
  });

  it('rejects a field outside the allow-list', () => {
    expect(() => service.parseSortParam('asc_password', ['name'])).toThrow(BadRequestException);
  });
});
