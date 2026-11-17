import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { PassportModule } from '@nestjs/passport';

import { appConfig } from '../../config/env.config';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { JwtStrategy } from './jwt.strategy';

@Module({
  imports: [
    PassportModule,
    JwtModule.register({
      secret: appConfig.JWT_SECRET,
      // Seconds, not "30m": @nestjs/jwt types expiresIn as number | ms.StringValue.
      signOptions: { algorithm: 'HS256', expiresIn: appConfig.JWT_EXPIRES_IN_SECONDS },
    }),
  ],
  controllers: [AuthController],
  providers: [AuthService, JwtStrategy],
  exports: [AuthService],
})
export class AuthModule {}
