import { LoginCard } from '@/features/auth';

// The layout renders <main> and CardTitle is a div, so the h1 comes from here.
export default function LoginPage() {
  return (
    <div className="flex min-h-screen items-center justify-center px-6">
      <h1 className="sr-only">Sign in</h1>
      <LoginCard />
    </div>
  );
}
