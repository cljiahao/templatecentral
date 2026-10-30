import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { Controller, Get, HttpCode, HttpStatus } from '@nestjs/common';
import { BaseService } from './base.service';

@ApiTags('Base')
@Controller()
export class BaseController {
  constructor(private readonly baseService: BaseService) {}

  @Get()
  @ApiOperation({ summary: 'Root endpoint' })
  getHello(): string {
    return this.baseService.getHello();
  }

  @Get('health')
  @ApiOperation({ summary: 'Health check' })
  @HttpCode(HttpStatus.OK)
  checkHealth(): { status: string } {
    return this.baseService.getHealth();
  }
}
