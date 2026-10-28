export const API_BASE =
  process.env.NEXT_PUBLIC_BASE_URL ?? 'http://localhost:3000';

export const isDev = process.env.NODE_ENV === 'development';
export const isProd = process.env.NODE_ENV === 'production';
