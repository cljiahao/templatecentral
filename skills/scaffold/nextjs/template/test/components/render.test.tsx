import type { ReactElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { FormProvider, useForm } from 'react-hook-form';
import { describe, expect, it, vi } from 'vitest';

import PublicLayout from '@/app/(public)/layout';
import Home from '@/app/(public)/page';
import DashboardPage from '@/app/dashboard/(overview)/page';
import DashboardLayout from '@/app/dashboard/layout';
import NotFound from '@/app/not-found';
import { Navbar, Providers, SiteFooter, ThemeProvider } from '@/components/layout';
import {
  BrandLogo,
  CustomCard,
  CustomDialog,
  CustomFormField,
  FloatingShape,
  LinkList,
  MediaCard,
  Pill,
  ThemeToggleButton,
} from '@/components/widgets';
import { getExampleItems } from '@/features/example/api/example-service';
import { ExampleCard } from '@/features/example/components/example-card';
import { ExampleList } from '@/features/example/components/example-list';
import { useExampleItems } from '@/features/example/hooks/use-example-items.query';

const pathname = vi.hoisted(() => ({ value: '/' }));
vi.mock('next/navigation', () => ({ usePathname: () => pathname.value }));
vi.mock('@/features/example/hooks/use-example-items.query', () => ({
  useExampleItems: vi.fn(),
}));

const html = (node: ReactElement) => renderToStaticMarkup(node);

function FieldHarness() {
  const methods = useForm({ defaultValues: { name: '' } });
  return (
    <FormProvider {...methods}>
      <CustomFormField name="name" label="Name" description="Your name">
        <input />
      </CustomFormField>
    </FormProvider>
  );
}

describe('components', () => {
  it('render their content and wire accessibility attributes', () => {
    const out = html(
      <>
        <BrandLogo />
        <FloatingShape />
        <Pill variant="solid">Tag</Pill>
        <CustomCard header="Head" description="Desc">
          Body
        </CustomCard>
        <ThemeToggleButton />
        <CustomDialog title="Title" description="Why" trigger={<button>Open</button>}>
          Inside
        </CustomDialog>
        <MediaCard title="T" mediaPosition="left">
          media
        </MediaCard>
        <MediaCard title="Only title" description="D" />
        <LinkList
          links={[
            { label: 'Docs', href: '/docs' },
            { label: 'Ext', href: 'https://x.test', target: '_blank' },
          ]}
        />
        <FieldHarness />
        <SiteFooter />
        <SiteFooter creditText="Credit" links={[{ label: 'L', href: '/l' }]} />
        <ThemeProvider attribute="class">
          <Providers>
            <p>child</p>
          </Providers>
        </ThemeProvider>
      </>
    );
    const expected = [
      'Head',
      'Only title',
      'noopener noreferrer',
      'name-description',
      'Credit',
      'child',
    ];
    expected.forEach((text) => expect(out).toContain(text));
  });

  it.each([
    ['/', false],
    ['/dashboard/x', true],
  ])('renders the navbar for %s', (path, isDashboard) => {
    pathname.value = path;
    expect(html(<Navbar />).includes('aria-current="page"')).toBe(isDashboard);
  });

  it('composes the pages from the layout', () => {
    const out = html(
      <>
        <PublicLayout>
          <Home />
        </PublicLayout>
        <DashboardLayout>
          <p>dash</p>
        </DashboardLayout>
        <NotFound />
      </>
    );
    expect(out).toContain('Page not found');
  });
});

describe('example feature', () => {
  const state = (patch: Partial<ReturnType<typeof useExampleItems>>) =>
    vi.mocked(useExampleItems).mockReturnValue(patch as ReturnType<typeof useExampleItems>);

  it.each([
    ['loading', { isPending: true }, 'Loading items'],
    ['failed', { isPending: false, error: new Error('x') }, 'Try again'],
    ['empty', { isPending: false, data: [] }, 'No items yet'],
    [
      'loaded',
      { isPending: false, data: [{ id: '1', title: 'One', description: 'd', status: 'active' }] },
      'One',
    ],
  ])('renders the %s state', (_label, patch, text) => {
    state(patch as never);
    expect(html(<ExampleList />)).toContain(text);
  });

  it('shows an inactive item and serves the example data', async () => {
    const item = { id: '2', title: 'Two', description: 'd', status: 'inactive' } as const;
    expect(html(<ExampleCard item={item} />)).toContain('Inactive');
    state({ isPending: false, data: [] });
    expect(html(<DashboardPage />)).toContain('Dashboard');
    expect((await getExampleItems()).length).toBeGreaterThan(0);
  });
});
