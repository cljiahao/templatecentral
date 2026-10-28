import { CustomCard } from '@/components/widgets';
import { cn } from '@/lib/utils';

import type { ExampleItem } from '../types';

const STATUS_LABEL: Record<ExampleItem['status'], string> = {
  active: 'Active',
  inactive: 'Inactive',
};

interface ExampleCardProps {
  item: ExampleItem;
}

export function ExampleCard({ item }: ExampleCardProps) {
  return (
    <CustomCard>
      <div className="flex items-start justify-between gap-2">
        <div>
          <h2 className="font-semibold">{item.title}</h2>
          <p className="mt-1 text-sm text-muted-foreground">{item.description}</p>
        </div>
        <span
          className={cn(
            'shrink-0 rounded-full px-2 py-0.5 text-xs font-medium',
            item.status === 'active'
              ? 'bg-secondary text-secondary-foreground'
              : 'bg-muted text-muted-foreground'
          )}
        >
          {STATUS_LABEL[item.status]}
        </span>
      </div>
    </CustomCard>
  );
}
