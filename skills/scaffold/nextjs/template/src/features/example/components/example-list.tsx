'use client';

import { Button } from '@/components/ui/button';

import { useExampleItems } from '../hooks/use-example-items.query';
import { ExampleCard } from './example-card';

export function ExampleList() {
  const { data: items, isPending, error, refetch } = useExampleItems();

  if (isPending) {
    return (
      <p role="status" className="text-sm text-muted-foreground">
        Loading items…
      </p>
    );
  }

  if (error) {
    return (
      <div role="alert" className="flex flex-col items-start gap-3">
        <p className="text-sm text-destructive">
          Couldn&apos;t load items. Check your connection and try again.
        </p>
        <Button variant="outline" onClick={() => refetch()}>
          Try again
        </Button>
      </div>
    );
  }

  if (!items?.length) {
    return (
      <p role="status" className="text-sm text-muted-foreground">
        No items yet. Add one to EXAMPLE_ITEMS in src/features/example/constants.ts to see it
        here.
      </p>
    );
  }

  return (
    <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
      {items.map((item) => (
        <ExampleCard key={item.id} item={item} />
      ))}
    </div>
  );
}
