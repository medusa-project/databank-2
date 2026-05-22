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

async function signInWithDeveloperAuth(page) {
  const response = await page.request.post("/auth/developer/callback", {
    form: {
      email: "a11y-tester@example.test",
      name: "A11y Tester",
      role: "depositor",
    },
  });

  expect(response.ok()).toBeTruthy();
}

async function createDataset(page) {
  await page.goto("/datasets/new");
  await page
    .locator('input[name="dataset[title]"]')
    .fill(`A11y Dataset ${Date.now()}`);
  await page.getByRole("button", { name: "Create Dataset", exact: true }).click();
  await expect(page).toHaveURL(/\/datasets\//);
}

test.describe("accessibility smoke checks", () => {
  test("home page has no critical axe violations in main content", async ({ page }) => {
    await expectNoA11yViolations(page, "/");
  });

  test("datasets index has no critical axe violations in main content", async ({ page }) => {
    await expectNoA11yViolations(page, "/datasets");
  });

  test("dataset show page has no critical axe violations in main content", async ({ page }) => {
    await signInWithDeveloperAuth(page);
    await createDataset(page);

    const accessibilityScanResults = await new AxeBuilder({ page })
      .include("main")
      .analyze();

    expect(
      accessibilityScanResults.violations,
      `Accessibility violations on dataset show page: ${JSON.stringify(accessibilityScanResults.violations, null, 2)}`,
    ).toEqual([]);
  });
});
