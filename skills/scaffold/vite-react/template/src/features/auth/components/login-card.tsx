import { Button } from '@/components/ui/button';
import { CustomCard } from '@/components/widgets';
import { ENV } from '@/lib/constants/env';
import { PAGE_ROUTES } from '@/lib/constants/routes';
import { useNavigate } from 'react-router';
import { useAuth } from '../hooks/use-auth';
import { DEV_USER } from './auth-provider';

export function LoginCard() {
  const { login } = useAuth();
  const navigate = useNavigate();

  const handleDevLogin = () => {
    login(DEV_USER);
    navigate(PAGE_ROUTES.DASHBOARD);
  };

  return (
    <CustomCard
      header="Sign in"
      headingLevel="h1"
      description="Choose how you want to sign in."
      className="w-full max-w-md shadow-lg"
    >
      <div className="flex flex-col gap-4">
        {/* TODO: add your SSO / OAuth sign-in button here. */}
        {ENV.IS_DEV && (
          <Button type="button" variant="outline" onClick={handleDevLogin}>
            Sign in as dev user
          </Button>
        )}
      </div>
    </CustomCard>
  );
}
