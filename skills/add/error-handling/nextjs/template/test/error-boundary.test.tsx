// @vitest-environment jsdom
import '@testing-library/jest-dom/vitest';
import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { ErrorBoundary } from '@/components/layout/error-boundary';

const Thrower = () => {
  throw new Error('internal detail');
};

describe('ErrorBoundary', () => {
  // NODE_ENV=test exercises the production message path.
  it('renders the generic fallback without leaking the error message', () => {
    render(
      <ErrorBoundary>
        <Thrower />
      </ErrorBoundary>
    );

    expect(screen.getByText(/unexpected error/i)).toBeInTheDocument();
    expect(screen.queryByText(/internal detail/)).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: /reload/i })).toBeInTheDocument();
  });
});
