import { createZodDto } from 'nestjs-zod';
import { z } from 'zod';

const registerSchema = z.object({
  email: z.email(),
  // 128-char cap bounds argon2 hashing cost on this unauthenticated endpoint.
  password: z.string().min(12).max(128),
  name: z.string().min(1),
});

const loginSchema = z.object({
  email: z.email(),
  password: z.string().min(1).max(128),
});

const tokenSchema = z.object({
  accessToken: z.string(),
  tokenType: z.literal('bearer'),
});

export class RegisterDto extends createZodDto(registerSchema) {}
export class LoginDto extends createZodDto(loginSchema) {}
export class TokenDto extends createZodDto(tokenSchema) {}
