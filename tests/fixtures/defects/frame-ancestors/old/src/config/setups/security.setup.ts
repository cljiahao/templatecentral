import helmet from '@fastify/helmet';

export const isDev = process.env.NODE_ENV === 'development';

export const securityOptions = {
  contentSecurityPolicy: {
    directives: {
      'frame-ancestors': isDev ? null : ["'none'"],
    },
  },
  frameguard: isDev ? false : { action: 'deny' },
};

export { helmet };
