import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { ExampleCard } from './example-card';

describe('ExampleCard', () => {
  const mockItem = {
    id: 'test-1',
    title: 'Test Title',
    description: 'Test description text',
  };

  it('renders the item title and description', () => {
    render(<ExampleCard item={mockItem} />);
    expect(screen.getByText('Test Title')).toBeInTheDocument();
    expect(screen.getByText('Test description text')).toBeInTheDocument();
  });
});
