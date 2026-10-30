import { createZodDto } from 'nestjs-zod';
import { z } from 'zod';

const CreateExampleSchema = z.object({
  name: z.string().min(1).max(100),
  description: z.string().max(500).optional(),
});

const UpdateExampleSchema = CreateExampleSchema.partial();

export class CreateExampleDto extends createZodDto(CreateExampleSchema) {}
export class UpdateExampleDto extends createZodDto(UpdateExampleSchema) {}
