import { PAGE_ROUTES } from '@/lib/constants/routes';
import { Navigate, Outlet } from 'react-router';
import { useAuth } from '../hooks/use-auth';

export function ProtectedRoute() {
  const { isAuthenticated, isLoading } = useAuth();

  if (isLoading) {
    return (
      <div className="flex-center py-16">
        <p role="status" className="text-muted-foreground">
          Checking your session…
        </p>
      </div>
    );
  }

  if (!isAuthenticated) {
    return <Navigate to={PAGE_ROUTES.LOGIN} replace />;
  }

  return <Outlet />;
}
