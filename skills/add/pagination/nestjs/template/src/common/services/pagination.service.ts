// src/common/services/pagination.service.ts
import { BadRequestException, Injectable } from '@nestjs/common';
import type { PaginationMetadata } from '../dto/pagination.dto';

export interface SortParam<F extends string> {
  field: F;
  direction: 'asc' | 'desc';
}

@Injectable()
export class PaginationService {
  calculateOffset(page: number, limit: number): number {
    return (page - 1) * limit;
  }

  createMetadata(page: number, limit: number, total: number): PaginationMetadata {
    return { page, limit, total, hasMore: page * limit < total };
  }

  /** Parses `asc_field` / `desc_field`; throws 400 listing the allowed fields when invalid. */
  parseSortParam<F extends string>(
    sort: string | undefined,
    allowedFields: readonly F[]
  ): SortParam<F> | null {
    if (!sort) return null;

    // Split on the FIRST underscore only — field names may be snake_case (e.g. asc_created_at).
    const separatorIndex = sort.indexOf('_');
    const direction = sort.slice(0, separatorIndex);
    const field = sort.slice(separatorIndex + 1) as F;
    if (allowedFields.includes(field) && (direction === 'asc' || direction === 'desc')) {
      return { field, direction };
    }
    // Pre-built in the error-handling filter's ErrorResponse shape so the allowed list survives it.
    throw new BadRequestException({
      error: 'Invalid sort field',
      details: { fieldErrors: { sort: [`Must be one of: ${allowedFields.join(', ')}`] } },
    });
  }
}
