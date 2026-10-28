import { cn } from '@/lib/utils';
import Image from 'next/image';

interface BrandLogoProps {
  className?: string;
}

export function BrandLogo({ className }: BrandLogoProps) {
  return (
    <div className={cn('relative h-full w-full', className)}>
      <Image
        src="/image_assets/logo.svg"
        alt="Logo"
        fill
        className="object-contain"
        priority
      />
    </div>
  );
}
