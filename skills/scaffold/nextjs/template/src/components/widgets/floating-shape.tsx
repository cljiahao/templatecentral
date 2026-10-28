import { cn } from '@/lib/utils';
import Image from 'next/image';

interface FloatingShapeProps {
  src?: string;
  alt?: string;
  imageClassName?: string;
  className?: string;
}

export function FloatingShape({
  src = '/image_assets/default-square.svg',
  alt = '',
  imageClassName,
  className,
}: FloatingShapeProps) {
  return (
    <div
      aria-hidden="true"
      className={cn(
        className,
        'pointer-events-none absolute hidden opacity-80 xl:block animate-float'
      )}
    >
      <Image
        src={src}
        alt={alt}
        fill
        className={cn(imageClassName, 'object-contain')}
      />
    </div>
  );
}
