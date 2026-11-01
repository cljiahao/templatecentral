import { Injectable, Logger, OnModuleInit, OnModuleDestroy } from '@nestjs/common';
import { drizzle } from 'drizzle-orm/postgres-js';
import { sql } from 'drizzle-orm';
import postgres from 'postgres';

import { appConfig, serviceConfig } from '../config/env.config';

@Injectable()
export class DrizzleService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(DrizzleService.name);
  private readonly client: ReturnType<typeof postgres>;
  // In v1 the first type parameter of `drizzle` is TRelations, not the schema —
  // tables are passed per query (`.from(users)`), so no schema generic is needed.
  readonly db: ReturnType<typeof drizzle>;

  constructor() {
    this.client = postgres(serviceConfig.DATABASE_URL, {
      // postgres.js defaults to plaintext. Local Docker Postgres serves no TLS, so only dev
      // skips it; 'verify-full' checks the certificate chain and hostname.
      ssl: appConfig.ENVIRONMENT === 'dev' ? false : 'verify-full',
    });
    this.db = drizzle({ client: this.client });
  }

  async onModuleInit() {
    try {
      await this.db.execute(sql`SELECT 1`);
      this.logger.log('Database connection verified');
    } catch (error) {
      this.logger.error('Database connection failed', error);
      throw error;
    }
  }

  async onModuleDestroy() {
    await this.client.end();
  }
}
