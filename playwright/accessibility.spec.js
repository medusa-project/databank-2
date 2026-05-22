const { test, expect } = require("@playwright/test");
const AxeBuilder = require("@axe-core/playwright").default;

async function expectNoA11yViolations(page, path) {
  await page.goto(path);

  // Scope to app content to reduce false positives from third-party chrome.
  const accessibilityScanResults = await new AxeBuilder({ page })
    .include("main")
    .analyze();

  expect(
    accessibilityScanResults.violations,
    `Accessibility violations on ${path}: ${JSON.stringify(accessibilityScanResults.violations, null, 2)}`,
  ).toEqual([]);
}

test.describe("accessibility smoke checks", () => {
  test("home page has no critical axe violations in main content", async ({ page }) => {
    await expectNoA11yViolations(page, "/");
  });

  test("datasets index has no critical axe violations in main content", async ({ page }) => {
    await expectNoA11yViolations(page, "/datasets");
  });
});
