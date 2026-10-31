import { toNextJsHandler } from 'better-auth/next-js';

import { auth } from '@/lib/auth';
import { withLogging } from '@/lib/utils/with-logging';

const handlers = toNextJsHandler(auth);

export const GET = withLogging(handlers.GET);
export const POST = withLogging(handlers.POST);
