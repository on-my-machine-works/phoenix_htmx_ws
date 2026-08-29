import { defineConfig } from '@playwright/test'

export default defineConfig({
  testDir: './test/browser',
  use: { baseURL: 'http://localhost:4000' },
  webServer: {
    command: 'mix run --no-halt',
    url: 'http://127.0.0.1:4000',
    reuseExistingServer: true,
    timeout: 120_000,
  },
})
