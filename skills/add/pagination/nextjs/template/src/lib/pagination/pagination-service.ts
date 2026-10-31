// src/lib/pagination/pagination-service.ts
import type { PaginationMetadata } from '@/lib/types/pagination';

export function calculateOffset(page: number, limit: number): number {
  return (page - 1) * limit;
}

export function createMetadata(page: number, limit: number, total: number): PaginationMetadata {
  return {
    page,
    limit,
    total,
    hasMore: page * limit < total,
  };
}

// Returns null unless the field is allow-listed — the only gate between client input and orderBy.
export function parseSortParam(
  sort: string | undefined,
  allowedFields: string[]
): { field: string; direction: 'asc' | 'desc' } | null {
  if (!sort) return null;

  // Split on the first underscore only — field names may contain underscores.
  const separatorIndex = sort.indexOf('_');
  if (separatorIndex === -1) return null;
  const direction = sort.slice(0, separatorIndex);
  const field = sort.slice(separatorIndex + 1);
  if (!allowedFields.includes(field) || !['asc', 'desc'].includes(direction)) {
    return null;
  }

  return { field, direction: direction as 'asc' | 'desc' };
}
