import { Button } from '@/components/ui/button';
import { useAuth } from '@/features/auth';
import { PAGE_ROUTES } from '@/lib/constants/routes';
import { cn } from '@/lib/utils';
import { Link, useLocation, useNavigate } from 'react-router';

const NAV_LINKS = [
  { label: 'Home', href: PAGE_ROUTES.HOME },
  { label: 'Dashboard', href: PAGE_ROUTES.DASHBOARD },
] as const;

export function Navbar() {
  const { pathname } = useLocation();
  const { isAuthenticated, logout } = useAuth();
  const navigate = useNavigate();

  const handleSignOut = async () => {
    await logout();
    navigate(PAGE_ROUTES.HOME);
  };

  return (
    <header className="bg-card sticky top-0 z-50 w-full border-b">
      <div className="max-w-site flex-between mx-auto gap-4 px-6 py-4">
        <Link to={PAGE_ROUTES.HOME} className="text-xl font-bold tracking-tight">
          templateCentral
        </Link>

        <nav aria-label="Main" className="flex items-center gap-6">
          {NAV_LINKS.map((link) => {
            const isActive = pathname === link.href;
            return (
              <Link
                key={link.href}
                to={link.href}
                // aria-current conveys the active link beyond colour.
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
          {isAuthenticated && (
            <Button type="button" variant="outline" size="sm" onClick={handleSignOut}>
              Sign out
            </Button>
          )}
        </nav>
      </div>
    </header>
  );
}
