const { defineConfig, devices } = require("@playwright/test");

const skipGlobalSetup = process.env.PW_SKIP_GLOBAL_SETUP === "1";

module.exports = defineConfig({
  globalSetup: skipGlobalSetup ? undefined : "./playwright/global-setup.js",
  testDir: "./playwright",
  timeout: 30_000,
  expect: {
    timeout: 10_000,
  },
  fullyParallel: false,
  retries: 0,
  workers: 1,
  use: {
    baseURL: "http://127.0.0.1:3100",
    trace: "on-first-retry",
  },
  projects: [
    {
      name: "chromium",
      use: {
        ...devices["Desktop Chrome"],
        viewport: { width: 1366, height: 900 },
      },
    },
  ],
  webServer: {
    command:
      "rm -f tmp/pids/server.pid && RAILS_ENV=test bin/rails db:prepare && RAILS_ENV=test bin/rails server -p 3100",
    port: 3100,
    reuseExistingServer: true,
    timeout: 120_000,
  },
});
