---
paths:
  - "src/**/*.controller.ts"
  - "src/**/*.dto.ts"
  - "src/app.module.ts"
---
- DTOs use `createZodDto` from `nestjs-zod`; class-validator is not used.
- Every endpoint carries `@ApiTags()` and `@ApiOperation()`.
- Register global pipes and filters in `app.module.ts`; apply auth guards at controller level.
