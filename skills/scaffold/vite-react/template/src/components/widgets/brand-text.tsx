import { cn } from '@/lib/utils';

interface BrandTextProps {
  className?: string;
}

export function BrandText({ className }: BrandTextProps) {
  return (
    <>
      <span className="text-brand-gradient">template</span>
      <span className={cn('text-foreground', className)}>Central</span>
    </>
  );
}
