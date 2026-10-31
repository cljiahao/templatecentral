import { LoginCard } from '@/features/auth';

// The (public) layout already renders <main>; a second one here is an a11y violation.
// CardTitle renders a <div>, so the page's level-one heading is supplied here.
export default function LoginPage() {
  return (
    <div className="flex min-h-screen items-center justify-center px-6">
      <h1 className="sr-only">Sign in</h1>
      <LoginCard />
    </div>
  );
}
