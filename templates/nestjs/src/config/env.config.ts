export const appConfig = {
  PROJECT_NAME: process.env.PROJECT_NAME || 'My Project',
  PROJECT_DESCRIPTION:
    process.env.PROJECT_DESCRIPTION ||
    'API built with [NestJS](https://nestjs.com/) + Fastify',
  PROJECT_VERSION: process.env.PROJECT_VERSION || '0.1.0',
  ENVIRONMENT: process.env.ENVIRONMENT || 'dev',
  PORT: Number.isFinite(parseInt(process.env.PORT ?? '', 10))
    ? parseInt(process.env.PORT!, 10)
    : 3000,
};

export const serviceConfig = {
  CLIENT_URL: (process.env.CLIENT_URL || 'http://localhost:3000').split(','),
};
