import { Global, Module, type OnModuleInit } from '@nestjs/common';
import { InjectConnection, MongooseModule } from '@nestjs/mongoose';
import { type Connection } from 'mongoose';
import { serviceConfig } from '../config/env.config';

@Global()
@Module({
  imports: [
    MongooseModule.forRoot(serviceConfig.MONGODB_URL),
  ],
})
export class DatabaseModule implements OnModuleInit {
  constructor(@InjectConnection() private readonly connection: Connection) {}

  // Mongoose builds schema indexes in the background: on a fresh database, inserts
  // made right after boot land before the unique index exists and duplicates get in.
  // Awaiting init() holds the boot until every forFeature model's indexes are built
  // (and fails it loudly if existing duplicates block a unique index).
  async onModuleInit() {
    await Promise.all(Object.values(this.connection.models).map((model) => model.init()));
  }
}
