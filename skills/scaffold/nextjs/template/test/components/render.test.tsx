import { createElement as h, type ReactElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { FormProvider, useForm } from 'react-hook-form';
import { describe, expect, it, vi } from 'vitest';

import PublicLayout from '@/app/(public)/layout';
import Home from '@/app/(public)/page';
import DashboardPage from '@/app/dashboard/(overview)/page';
import DashboardLayout from '@/app/dashboard/layout';
import NotFound from '@/app/not-found';
import { Navbar, Providers, SiteFooter } from '@/components/layout';
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
vi.mock('@/features/example/hooks/use-example-items.query', () => ({ useExampleItems: vi.fn() }));

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
  const links = [
    { label: 'Docs', href: '/docs' },
    { label: 'Ext', href: 'https://x.test', target: '_blank' },
  ];
  // Each row renders alone: [name, element, strings it must contain, strings it must not].
  const cases: [string, ReactElement, string[], string[]?][] = [
    ['BrandLogo', h(BrandLogo), ['alt="Logo"']],
    ['FloatingShape', h(FloatingShape), ['aria-hidden="true"']],
    [
      'Solid',
      h(Pill, { variant: 'solid', children: 'Tag' }),
      ['Tag', 'text-background'],
      ['bg-card'],
    ],
    ['Outline', h(Pill, { children: 'Tag' }), ['bg-card'], ['text-background']],
    ['Card', h(CustomCard, { header: 'Hd', description: 'Ds' }, 'Bd'), ['Hd', 'Ds', 'Bd']],
    ['ThemeToggleButton', h(ThemeToggleButton), ['aria-label="Toggle dark mode"']],
    [
      'Dialog',
      h(CustomDialog, {
        title: 'T',
        description: 'Why',
        trigger: h('b', null, 'Open'),
        children: 'x',
      }),
      ['Open'],
    ],
    ['Media', h(MediaCard, { title: 'T', mediaPosition: 'left' }, 'media'), ['media', 'flex-row']],
    ['Media bare', h(MediaCard, { title: 'Only', description: 'D' }), ['Only', '>D<'], ['media']],
    ['Link', h(LinkList, { links }), ['href="/docs"', 'target="_blank" rel="noopener noreferrer"']],
    ['Link int', h(LinkList, { links: links.slice(0, 1) }), ['href="/docs"'], ['rel=']],
    [
      'Field',
      h(FieldHarness),
      ['aria-describedby="name-description"', 'id="name-description"', 'for="name"', 'id="name"'],
    ],
    ['SiteFooter default', h(SiteFooter), ['Built with templateCentral'], ['<nav']],
    [
      'SiteFooter custom',
      h(SiteFooter, { creditText: 'Credit', links: [{ label: 'L', href: '/l' }] }),
      ['Credit', 'href="/l"', 'aria-label="Footer"'],
      ['Built with templateCentral'],
    ],
    ['Providers', h(Providers, null, h('p', null, 'child')), ['<p>child</p>']],
  ];

  it.each(cases)('%s renders its own content and attributes', (_name, element, has, lacks = []) => {
    const out = html(element);
    has.forEach((text) => expect(out).toContain(text));
    lacks.forEach((text) => expect(out).not.toContain(text));
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
