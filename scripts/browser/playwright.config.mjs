import { defineConfig } from '@playwright/test';
import { readFileSync } from 'node:fs';

const config = JSON.parse(readFileSync(new URL('../../example/app.json', import.meta.url)));
const baseURL = `http://127.0.0.1:4173${config.expo.experiments.baseUrl}/`;

export default defineConfig({
  testDir: '.',
  testMatch: '*.spec.mjs',
  workers: 1,
  retries: 0,
  timeout: 45000,
  use: {
    baseURL,
    browserName: 'chromium',
    viewport: { width: 1280, height: 960 },
    screenshot: 'only-on-failure',
    trace: 'retain-on-failure',
  },
  webServer: { command: 'node serve.mjs', url: baseURL, timeout: 15000 },
});
