export type ExampleUpdate = Partial<Record<'name' | 'description', string | undefined>>;

export interface ExampleItem {
  id: string;
  name: string;
  description?: string | undefined;
  createdAt: string;
  updatedAt: string;
}
