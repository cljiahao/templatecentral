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
  alt = 'default-square',
  imageClassName,
  className,
}: FloatingShapeProps) {
  return (
    <div
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
