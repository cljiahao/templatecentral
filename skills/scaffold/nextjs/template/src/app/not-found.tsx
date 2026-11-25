import Link from 'next/link';

import { Navbar, SiteFooter } from '@/components/layout';
import { PAGE_ROUTES } from '@/lib/constants/routes';

export default function NotFound() {
  return (
    <div className="flex min-h-screen flex-col">
      <Navbar />
      <main className="flex-center flex-1 flex-col gap-4 px-6 text-center">
        <h1 className="text-3xl font-bold tracking-tight">Page not found</h1>
        <p className="text-muted-foreground max-w-md">
          This page doesn&apos;t exist or has moved. Check the address, or go to the home page.
        </p>
        <Link
          href={PAGE_ROUTES.HOME}
          className="text-primary hover:text-primary-hover mt-2 text-sm font-medium underline underline-offset-4"
        >
          Go to the home page
        </Link>
      </main>
      <SiteFooter />
    </div>
  );
}
