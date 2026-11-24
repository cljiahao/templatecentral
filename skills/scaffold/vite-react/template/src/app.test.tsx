import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { FormProvider, useForm } from 'react-hook-form';
import { describe, expect, it, vi } from 'vitest';

import { ErrorBoundary } from '@/components/layout';
import { SiteFooter } from '@/components/layout/site-footer';
import { CustomDialog, CustomFormField, LinkList, MediaCard, Pill } from '@/components/widgets';
import { App } from './app';

function Boom(): never {
  throw new Error('exploded');
}

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

describe('App', () => {
  it('walks home, dashboard, sign out, login and an unknown page', async () => {
    window.history.pushState({}, '', '/');
    render(<App />);
    fireEvent.click(screen.getByRole('link', { name: 'Dashboard' }));
    expect(await screen.findByText('Feature modules')).toBeInTheDocument();

    fireEvent.click(screen.getByRole('button', { name: 'Sign out' }));
    await waitFor(() => expect(window.location.pathname).toBe('/'));
    expect(screen.queryByRole('button', { name: 'Sign out' })).not.toBeInTheDocument();

    fireEvent.click(screen.getByRole('link', { name: 'Dashboard' }));
    fireEvent.click(await screen.findByRole('button', { name: 'Sign in as dev user' }));
    expect(await screen.findByRole('heading', { name: 'Dashboard' })).toBeInTheDocument();

    window.history.pushState({}, '', '/missing');
    render(<App />);
    expect(await screen.findByText('Page not found')).toBeInTheDocument();
  });
});

describe('ErrorBoundary', () => {
  it('shows the message, then recovers when the retry no longer throws', () => {
    vi.spyOn(console, 'error').mockImplementation(() => undefined);
    let fail = true;
    const Child = () => (fail ? <Boom /> : <p>recovered</p>);
    render(
      <ErrorBoundary>
        <Child />
      </ErrorBoundary>
    );
    expect(screen.getByText('exploded')).toBeInTheDocument();
    fail = false;
    fireEvent.click(screen.getByRole('button', { name: 'Try again' }));
    expect(screen.getByText('recovered')).toBeInTheDocument();
  });

  it('renders the fallback when one is given', () => {
    vi.spyOn(console, 'error').mockImplementation(() => undefined);
    render(
      <ErrorBoundary fallback={<p>fallback</p>}>
        <Boom />
      </ErrorBoundary>
    );
    expect(screen.getByText('fallback')).toBeInTheDocument();
  });
});

describe('widgets', () => {
  it('render their content', () => {
    render(
      <>
        <Pill variant="solid">Tag</Pill>
        <MediaCard title="Media" description="D" mediaPosition="left">
          media
        </MediaCard>
        <SiteFooter />
        <LinkList links={[{ label: 'Ext', href: 'https://x.test', target: '_blank' }]} />
        <FieldHarness />
      </>
    );
    expect(screen.getByRole('link', { name: 'Ext' })).toHaveAttribute('rel', 'noopener noreferrer');
    expect(screen.getByLabelText('Name')).toHaveAttribute('aria-describedby', 'name-description');
  });

  it('shows an open dialog with its title and description', () => {
    render(
      <CustomDialog open title="Title" description="Why">
        Inside
      </CustomDialog>
    );
    expect(screen.getByRole('dialog', { name: 'Title' })).toHaveTextContent('Inside');
  });
});
