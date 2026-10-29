import { Outlet } from 'react-router';
import { Navbar } from './navbar';
import { SiteFooter } from './site-footer';

export function RootLayout() {
  return (
    <div className="flex min-h-screen flex-col">
      <Navbar />
      <main className="flex-1">
        <Outlet />
      </main>
      <SiteFooter />
    </div>
  );
}
