import { Injectable, Logger, NotImplementedException } from '@nestjs/common';

import type { LoginDto, RegisterDto, TokenDto } from './auth.dto';

// A missing database means 501, not 401; the remediation goes to the log, never the response.
const STUB_REMEDIATION =
  'AuthService is a stub. Run templatecentral:add (database) to generate the real implementation.';

@Injectable()
export class AuthService {
  private readonly logger = new Logger(AuthService.name);

  register(_dto: RegisterDto) {
    this.logger.error(STUB_REMEDIATION);
    throw new NotImplementedException('Not implemented.');
  }

  // Typed so cookie mode's login call compiles before the database guide replaces this stub.
  login(_dto: LoginDto): Promise<TokenDto> {
    this.logger.error(STUB_REMEDIATION);
    throw new NotImplementedException('Not implemented.');
  }
}
