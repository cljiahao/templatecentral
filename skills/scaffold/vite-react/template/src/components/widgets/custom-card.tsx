import { cn } from '@/lib/utils';
import type { ReactNode } from 'react';

interface CustomCardProps {
  header: string;
  /** Heading element for `header` — pick the level that fits the page outline. @default "h2" */
  headingLevel?: 'h1' | 'h2' | 'h3';
  description?: string;
  children?: ReactNode;
  className?: string;
}

export function CustomCard({
  header,
  headingLevel: Heading = 'h2',
  description,
  children,
  className,
}: CustomCardProps) {
  return (
    <div className={cn('bg-card rounded-lg border p-6 shadow-xs', className)}>
      <Heading className="text-lg font-semibold">{header}</Heading>
      {description && <p className="text-muted-foreground mt-1 text-sm">{description}</p>}
      {children && <div className="mt-4">{children}</div>}
    </div>
  );
}
