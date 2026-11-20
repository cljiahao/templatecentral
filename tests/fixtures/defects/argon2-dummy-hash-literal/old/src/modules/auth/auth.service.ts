import { ConflictException, Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { InjectModel } from '@nestjs/mongoose';
import * as argon2 from 'argon2';
import { Model } from 'mongoose';

import { User, type UserDocument } from './schemas/user.schema';
import type { LoginDto, RegisterDto } from './auth.dto';

// Verified on the miss path so an unknown email costs the same as a wrong
// password — without it, response timing leaks which accounts exist.
const DUMMY_HASH =
  '$argon2id$v=19$m=65536,t=3,p=1$c29tZXNhbHRzb21lc2E$Rdo0OMHkQXBTOTBqNCn0mPvBGiLxvGBIbxKZ0nJ0Aqo';

@Injectable()
export class AuthService {
  constructor(
    private readonly jwtService: JwtService,
    @InjectModel(User.name) private readonly userModel: Model<UserDocument>,
  ) {}

  async register(dto: RegisterDto) {
    const existing = await this.userModel.findOne({ email: dto.email }).exec();
    if (existing) throw new ConflictException('Email already registered.');

    // argon2id by default
    const hashedPassword = await argon2.hash(dto.password);
    const user = await this.userModel.create({
      email: dto.email,
      name: dto.name,
      hashedPassword,
    });
    return { id: user._id.toString(), email: user.email, name: user.name };
  }

  async login(dto: LoginDto) {
    // `hashedPassword` is `select: false` on the schema — opt in only here.
    const user = await this.userModel
      .findOne({ email: dto.email })
      .select('+hashedPassword')
      .exec();
    const passwordOk = await argon2.verify(
      user?.hashedPassword ?? DUMMY_HASH,
      dto.password,
    );
    if (!user || !passwordOk) {
      throw new UnauthorizedException('Invalid credentials.');
    }
    return {
      accessToken: this.jwtService.sign({ sub: user._id.toString(), email: user.email }),
      tokenType: 'bearer' as const,
    };
  }
}
