// src/hooks/use-pagination.ts
import { keepPreviousData, useQuery } from '@tanstack/react-query';
import { useState } from 'react';

export interface Paginated<T> {
  items: T[];
  pagination: { page: number; limit: number; total: number; hasMore: boolean };
}

interface UsePaginationOptions {
  initialPage?: number;
  pageSize?: number;
  enabled?: boolean;
}

export function usePagination<T>(
  queryKey: readonly unknown[],
  fetchFn: (page: number, limit: number, signal: AbortSignal) => Promise<Paginated<T>>,
  { initialPage = 1, pageSize = 10, enabled = true }: UsePaginationOptions = {}
) {
  const [page, setPage] = useState(initialPage);

  const { data, isPending, isFetching, error } = useQuery({
    // pageSize is in the key so two lists with different sizes never share a cache entry.
    queryKey: [...queryKey, { page, pageSize }],
    queryFn: ({ signal }) => fetchFn(page, pageSize, signal),
    enabled,
    // Keeps the previous page on screen (isFetching) instead of unmounting to isPending.
    placeholderData: keepPreviousData,
  });

  return {
    items: data?.items ?? [],
    pagination: data?.pagination,
    page,
    isPending,
    isFetching,
    error,
    nextPage: () => {
      if (data?.pagination.hasMore) setPage((p) => p + 1);
    },
    prevPage: () => setPage((p) => Math.max(1, p - 1)),
  };
}
