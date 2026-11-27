import { render } from '@testing-library/react';
import { Card } from './Card';

it('matches the snapshot', () => {
  const { container } = render(<Card title="t" />);
  expect(container).toMatchSnapshot();
});
