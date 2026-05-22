const { test, expect } = require("@playwright/test");

async function signInWithDeveloperAuth(page) {
  const response = await page.request.post("/auth/developer/callback", {
    form: {
      email: "agreement-flow-tester@example.test",
      name: "Agreement Flow Tester",
      role: "depositor",
    },
  });

  expect(response.ok()).toBeTruthy();
}

test.describe("pre-deposit to deposit agreement workflow", () => {
  test("continues to agreement, creates draft, and persists agreement answers", async ({ page }) => {
    await signInWithDeveloperAuth(page);

    await page.goto("/datasets/pre_deposit");
    await expect(page).toHaveURL(/\/datasets\/pre_deposit$/);

    await page.getByRole("link", { name: "Continue", exact: true }).click();
    await expect(page).toHaveURL(/\/datasets\/new$/);
    await expect(page.getByRole("heading", { name: "Deposit Agreement", exact: true })).toBeVisible();

    await page.locator('input[name="dataset[have_permission]"][value="yes"]').check();
    await page.locator('input[name="dataset[removed_private]"][value="yes"]').check();
    await page.locator('input[name="dataset[agree]"][value="yes"]').check();

    await page.getByRole("button", { name: "Submit", exact: true }).click();
    await expect(page).toHaveURL(/\/datasets\/[^/]+\/edit$/);

    await expect(page.locator('input[name="dataset[have_permission]"]')).toHaveValue("yes");
    await expect(page.locator('input[name="dataset[removed_private]"]')).toHaveValue("yes");
    await expect(page.locator('input[name="dataset[agree]"]')).toHaveValue("yes");
  });

  test("shows warning for unacceptable answers and only enables submit for acceptable answers", async ({ page }) => {
    await signInWithDeveloperAuth(page);
    await page.goto("/datasets/new");

    const submitButton = page.locator("#agree-button");
    const warning = page.locator(".deposit-agreement-selection-warning");

    await expect(submitButton).toBeDisabled();
    await expect(warning).toBeHidden();

    await page.locator("#owner-no").check();
    await expect(submitButton).toBeDisabled();
    await expect(warning).toContainText("Selection Alert");
    await expect(warning).toContainText("not ready to deposit your dataset");

    await page.locator("#owner-yes").check();
    await expect(submitButton).toBeDisabled();
    await expect(warning).toBeHidden();

    await page.locator("#private-no").check();
    await expect(submitButton).toBeDisabled();
    await expect(warning).toContainText("Selection Alert");

    await page.locator("#private-na").check();
    await expect(submitButton).toBeDisabled();
    await expect(warning).toBeHidden();

    await page.locator("#agree-no").check();
    await expect(submitButton).toBeDisabled();
    await expect(warning).toContainText("Selection Alert");

    await page.locator("#agree-yes").check();
    await expect(warning).toBeHidden();
    await expect(submitButton).toBeEnabled();
  });
});
