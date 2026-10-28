'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';

import { Button } from '@/components/ui/button';
import { BrandText } from '@/components/widgets';
import { PAGE_ROUTES } from '@/lib/constants/routes';
import { cn } from '@/lib/utils';

export function Navbar() {
  const pathname = usePathname();
  const rootPath = `/${pathname.split('/')[1]}`;
  const isDashboard = rootPath === PAGE_ROUTES.DASHBOARD;

  return (
    <header
      className={cn(
        isDashboard
          ? 'sticky top-0 z-50 w-full'
          : 'max-w-site fixed inset-x-0 top-0 z-50 mx-auto px-4 pt-10',
      )}
    >
      <div
        className={cn(
          'flex-between min-h-20 gap-4 bg-card px-6 py-3 shadow-lg',
          isDashboard ? 'border-b' : 'rounded-2xl border',
        )}
      >
        <Link href={PAGE_ROUTES.HOME} className="text-xl font-bold tracking-tight">
          <BrandText />
        </Link>

        <nav aria-label="Main">
          <Button asChild size="lg">
            <Link
              href={PAGE_ROUTES.DASHBOARD}
              aria-current={isDashboard ? 'page' : undefined}
            >
              Dashboard
            </Link>
          </Button>
        </nav>
      </div>
    </header>
  );
}
