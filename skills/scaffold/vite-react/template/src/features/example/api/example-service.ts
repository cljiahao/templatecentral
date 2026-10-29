import { EXAMPLE_ITEMS } from '../constants';
import type { ExampleItem } from '../types';

export const ExampleService = {
  getAll: (): ExampleItem[] => {
    return [...EXAMPLE_ITEMS];
  },

  getById: (id: string): ExampleItem | undefined => {
    return EXAMPLE_ITEMS.find((item) => item.id === id);
  },
};
