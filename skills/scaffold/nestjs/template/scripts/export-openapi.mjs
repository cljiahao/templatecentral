// Prints the OpenAPI document from the compiled app, with no server, no port, no network.
import { existsSync } from 'node:fs';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const dist = fileURLToPath(new URL('../dist/', import.meta.url));

if (!existsSync(`${dist}app.module.js`)) {
  console.error('export-openapi: dist/ is missing. Run `pnpm build` first.');
  process.exit(1);
}

const { NestFactory } = require('@nestjs/core');
const { FastifyAdapter } = require('@nestjs/platform-fastify');
const { AppModule } = require(`${dist}app.module.js`);
const { buildOpenApiDocument } = require(`${dist}config/setups/swagger.setup.js`);

const app = await NestFactory.create(AppModule, new FastifyAdapter(), { logger: false, preview: true });
process.stdout.write(`${JSON.stringify(buildOpenApiDocument(app), null, 2)}\n`);
await app.close();
