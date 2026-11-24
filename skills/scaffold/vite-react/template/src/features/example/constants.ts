export const EXAMPLE_ITEMS = [
  {
    id: 'item-1',
    title: 'Feature modules',
    description: 'Add features under src/features/<name>/ with api/, components/, hooks/, schemas/.',
  },
  {
    id: 'item-2',
    title: 'Data fetching',
    description: 'Query hooks live in src/features/<name>/hooks/ and wrap TanStack Query.',
  },
  {
    id: 'item-3',
    title: 'shadcn/ui',
    description: 'Add UI primitives with npx shadcn@latest add <component>.',
  },
] as const;
