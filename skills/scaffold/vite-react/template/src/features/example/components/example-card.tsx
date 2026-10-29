import { CustomCard } from '@/components/widgets';
import type { ExampleItem } from '../types';

interface ExampleCardProps {
  item: ExampleItem;
}

export function ExampleCard({ item }: ExampleCardProps) {
  return <CustomCard header={item.title} description={item.description} />;
}
