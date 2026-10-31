import { Injectable, Logger, NotImplementedException } from '@nestjs/common';

import type { LoginDto, RegisterDto, TokenDto } from './auth.dto';

// A missing database is an unimplemented feature (501), not a rejected credential (401):
// returning 401 would tell clients the credentials were wrong when nothing was checked.
// The remediation ("run templatecentral:add (database)") is operator-facing — it goes to
// the server log, never into the HTTP response body.
const STUB_REMEDIATION =
  'AuthService is a stub. Run templatecentral:add (database) to generate the real implementation.';

@Injectable()
export class AuthService {
  private readonly logger = new Logger(AuthService.name);

  register(_dto: RegisterDto) {
    this.logger.error(STUB_REMEDIATION);
    throw new NotImplementedException('Not implemented.');
  }

  // Typed so cookie mode's `await this.authService.login(dto)` compiles before the database
  // guide replaces this stub with the real (async) implementation.
  login(_dto: LoginDto): Promise<TokenDto> {
    this.logger.error(STUB_REMEDIATION);
    throw new NotImplementedException('Not implemented.');
  }
}
