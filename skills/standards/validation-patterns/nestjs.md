<!-- ref: standards/validation-patterns/nestjs.md
     loaded-by: standards/SKILL.md
     prereq: Stack = nestjs. Do not invoke this file directly — it is loaded at runtime by the templatecentral:standards skill. -->
### NestJS (TypeScript + Zod via nestjs-zod)

The global `ZodValidationPipe` (`APP_PIPE`) validates every `createZodDto` `@Body()`/`@Query()` type. Plain-typed params (`@Param('id') id: string`) are not validated, so give them an explicit pipe.

DTOs live in `src/modules/<feature>/dto/` as `createZodDto(schema)` classes. Bound pagination: `page` `.max(10_000)`, `limit` `.max(100)` with `z.coerce.number()` and defaults. Path ids: `@Param('id', new ZodValidationPipe(z.uuid()))`.

**1. File uploads and controller**

> **File uploads with Fastify**: `FileInterceptor` from `@nestjs/platform-express` is incompatible with the Fastify adapter. Use `@fastify/multipart` (`pnpm add @fastify/multipart`), registered inside `createApp()` (`src/app.factory.ts`) before `app.init()` — `register` returns a promise, so await it:
> ```ts
> // src/app.factory.ts — inside createApp(), before app.init()
> const fastify = app.getHttpAdapter().getInstance();
> await fastify.register(import('@fastify/multipart'), {
>   limits: { fileSize: 10 * 1024 * 1024, files: 1 },
> });
> ```

The upload handler takes `@Req() req: FastifyRequest`, reads `req.isMultipart() ? await req.file() : undefined`, throws `BadRequestException('File is required')` when absent, and passes the file to the service. Document it with `@ApiConsumes('multipart/form-data')` and an `@ApiBody` binary `file` property. Controllers validate at the boundary and delegate everything else.

**2. Service — upload checks live here, not in the controller**

```ts
// src/modules/projects/projects.service.ts — upload excerpt
import { randomUUID } from 'node:crypto';
import type { MultipartFile } from '@fastify/multipart';
import { BadRequestException, Injectable, PayloadTooLargeException } from '@nestjs/common';

const ALLOWED_TYPES = ['image/jpeg', 'image/png', 'application/pdf'];

@Injectable()
export class ProjectsService {
  async storeUpload(file: MultipartFile) {
    // mimetype is client-supplied: for high assurance, also verify magic bytes with a detector such as file-type.
    if (!ALLOWED_TYPES.includes(file.mimetype)) {
      throw new BadRequestException('File type not allowed');
    }

    // toBuffer() throws a plain Error past limits.fileSize, which bypasses HttpExceptionFilter and surfaces as an unformatted 500.
    let buffer: Buffer;
    try {
      buffer = await file.toBuffer();
    } catch {
      throw new PayloadTooLargeException('File exceeds the maximum allowed size');
    }

    // file.filename is attacker-controlled, including ../, absolute paths and NUL bytes: never put it in a storage path, only in sanitized display metadata.
    const storageKey = randomUUID();
    const displayName = file.filename.replace(/[^\w.\- ]/g, '_').slice(0, 255);

    return { storageKey, displayName, size: buffer.byteLength };
  }
}
```

Verify: an invalid body or non-UUID path param returns 400; `pnpm test`.

## After Writing Code

Dispatch in order:
1. build utility (`cat "<skill-dir>/../build/SKILL.md"`) — validate compilation
2. review utility (`cat "<skill-dir>/../review/SKILL.md"`) — check code standards
