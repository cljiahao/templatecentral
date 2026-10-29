import { PAGE_ROUTES } from '@/lib/constants/routes';
import { cn } from '@/lib/utils';
import { Link, useLocation } from 'react-router';

const NAV_LINKS = [
  { label: 'Home', href: PAGE_ROUTES.HOME },
  { label: 'Dashboard', href: PAGE_ROUTES.DASHBOARD },
] as const;

export function Navbar() {
  const { pathname } = useLocation();

  return (
    <header className="bg-card sticky top-0 z-50 w-full border-b">
      <div className="max-w-site flex-between mx-auto gap-4 px-6 py-4">
        <Link to={PAGE_ROUTES.HOME} className="text-xl font-bold tracking-tight">
          templateCentral
        </Link>

        <nav aria-label="Main" className="flex gap-6">
          {NAV_LINKS.map((link) => {
            const isActive = pathname === link.href;
            return (
              <Link
                key={link.href}
                to={link.href}
                // Colour alone cannot convey the active link — aria-current is what
                // reaches assistive tech and users who can't distinguish the hue.
                aria-current={isActive ? 'page' : undefined}
                className={cn(
                  'hover:text-primary text-sm font-medium transition-colors',
                  isActive ? 'text-primary' : 'text-muted-foreground'
                )}
              >
                {link.label}
              </Link>
            );
          })}
        </nav>
      </div>
    </header>
  );
}
