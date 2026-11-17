import { config } from 'dotenv';

config({ quiet: true });

import { runBootstrap } from './bootstrap';

void runBootstrap();
