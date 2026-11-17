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

  // Awaiting init() holds boot until unique indexes exist, so early inserts cannot create duplicates.
  async onModuleInit() {
    await Promise.all(Object.values(this.connection.models).map((model) => model.init()));
  }
}
