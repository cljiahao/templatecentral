import { Button } from '@/components/ui/button';
import { PAGE_ROUTES } from '@/lib/constants/routes';
import { Link } from 'react-router';

export function HomePage() {
  return (
    <div className="max-w-site mx-auto w-full px-6 py-16">
      <div className="flex flex-col items-center gap-6 text-center">
        <h1 className="text-4xl font-bold tracking-tight sm:text-5xl">Vite + React Template</h1>
        <p className="text-muted-foreground max-w-xl text-lg">
          Start building here. Edit src/pages/home.tsx to replace this page.
        </p>
        <Button asChild size="lg">
          <Link to={PAGE_ROUTES.DASHBOARD}>Open dashboard</Link>
        </Button>
      </div>
    </div>
  );
}
