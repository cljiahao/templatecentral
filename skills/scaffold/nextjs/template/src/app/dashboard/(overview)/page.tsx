import { ExampleList } from '@/features/example';

export default function DashboardPage() {
  return (
    <div className="max-w-site mx-auto w-full px-6 py-12">
      <h1 className="text-3xl font-bold tracking-tight">Dashboard</h1>
      <p className="mt-2 text-muted-foreground">
        These items come from the example feature module. Replace them with your own data.
      </p>
      <div className="mt-8">
        <ExampleList />
      </div>
    </div>
  );
}
