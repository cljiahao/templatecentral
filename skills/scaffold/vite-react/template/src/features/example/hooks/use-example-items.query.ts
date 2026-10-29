import { useQuery } from '@tanstack/react-query';
import { ExampleService } from '../api';

export const useExampleItems = () => {
  return useQuery({
    queryKey: ['example-items'],
    queryFn: () => ExampleService.getAll(),
  });
};
