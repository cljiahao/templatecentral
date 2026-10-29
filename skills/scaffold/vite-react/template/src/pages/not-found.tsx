import { PAGE_ROUTES } from '@/lib/constants/routes';
import { Link } from 'react-router';

export function NotFoundPage() {
  return (
    <div className="flex-center min-h-[60vh] flex-col gap-4 px-6 text-center">
      <h1 className="text-3xl font-bold tracking-tight">Page not found</h1>
      <p className="text-muted-foreground max-w-md">
        This page doesn&apos;t exist or has moved. Check the address, or go to the home page.
      </p>
      <Link
        to={PAGE_ROUTES.HOME}
        className="text-primary hover:text-primary-hover mt-2 text-sm font-medium underline underline-offset-4"
      >
        Go to the home page
      </Link>
    </div>
  );
}
