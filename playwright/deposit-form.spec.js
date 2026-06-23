const { test, expect } = require("@playwright/test");

async function signInWithDeveloperAuth(page) {
  await signInWithDeveloperAuthRole(page, "depositor");
}

async function signInWithDeveloperAuthRole(page, role) {
  const response = await page.request.post("/auth/developer/callback", {
    form: {
      email: "deposit-form-tester@example.test",
      name: "Deposit Form Tester",
      role,
    },
  });

  expect(response.ok()).toBeTruthy();
}

async function createDatasetAndOpenEdit(page) {
  await page.goto("/datasets/new");
  await page.locator('#owner-yes').check();
  await page.locator('#private-yes').check();
  await page.locator('#agree-yes').check();
  await page.getByRole("button", { name: "Submit", exact: true }).click();
  await expect(page).toHaveURL(/\/datasets\/.*\/edit$/);

  await page.locator('input[name="dataset[title]"]').fill(`Deposit Form Dataset ${Date.now()}`);
  await page.locator('select[name="dataset[license]"]').selectOption("CC0");
}

async function addCreatorRowFromToolbar(page) {
  await page.locator('button[data-action="deposit-form#addCreatorRow"]').click();
}

async function fillIndividualCreatorRow(page, index, { familyName, givenName, email }) {
  const row = page.locator("#creator-rows .idb-nested-row").nth(index);
  await row.locator('input[name*="[family_name]"]').fill(familyName);
  await row.locator('input[name*="[given_name]"]').fill(givenName);
  await row.locator('input[name*="[email]"]').fill(email);
}

async function fillOrganizationCreatorRow(page, index, { institutionName, email }) {
  const row = page.locator("#creator-rows .idb-nested-row").nth(index);
  await row.locator('input[name*="[institution_name]"]').fill(institutionName);
  await row.locator('input[name*="[email]"]').fill(email);
}

async function selectPrimaryContact(page, index = 0) {
  await page.locator('#creator-rows input[type="radio"][name="primary_contact_index"]').nth(index).check();
}

test.describe("deposit form parity behavior", () => {
  test("reorders creator rows and updates persisted row positions", async ({ page }) => {
    await signInWithDeveloperAuth(page);
    await createDatasetAndOpenEdit(page);

    const creatorRows = page.locator("#creator-rows .idb-nested-row");

    await creatorRows.nth(0).locator('input[name*="[family_name]"]').fill("Alpha");
    await addCreatorRowFromToolbar(page);
    await expect(creatorRows).toHaveCount(2);
    await creatorRows.nth(1).locator('input[name*="[family_name]"]').fill("Beta");

    await creatorRows.nth(1).locator('button[data-action="deposit-form#moveRowUp"]').click();

    await expect(creatorRows.nth(0).locator('input[name*="[family_name]"]')).toHaveValue("Beta");
    await expect(creatorRows.nth(1).locator('input[name*="[family_name]"]')).toHaveValue("Alpha");

    await expect(creatorRows.nth(0).locator('input[name*="[row_position]"]')).toHaveValue("1");
    await expect(creatorRows.nth(1).locator('input[name*="[row_position]"]')).toHaveValue("2");
  });

  test("supports ORCID lookup dialog with focus restore and field application", async ({ page }) => {
    await signInWithDeveloperAuth(page);

    await page.route("**/datasets/*/creators/orcid_lookup**", async (route) => {
      const url = new URL(route.request().url());
      const familyName = url.searchParams.get("family_name") || "";
      const givenName = url.searchParams.get("given_name") || "";

      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          results: [
            {
              orcid: "0000-0002-1825-0097",
              family_name: familyName || "Lovelace",
              given_name: givenName || "Ada",
              institution: "Analytical Engine Institute",
            },
          ],
        }),
      });
    });

    await createDatasetAndOpenEdit(page);

    const firstCreatorRow = page.locator("#creator-rows .idb-nested-row").first();
    const lookupButton = firstCreatorRow.getByRole("button", { name: "Look Up ORCID", exact: true });

    await firstCreatorRow.locator('input[name*="[family_name]"]').fill("Lovelace");
    await firstCreatorRow.locator('input[name*="[given_name]"]').fill("Ada");

    await lookupButton.click();

    const dialog = page.locator("#orcid-lookup-dialog");
    await expect(dialog).toBeVisible();
    await expect(page.locator("#orcid-family-name")).toBeFocused();

    await page.getByRole("button", { name: "Search", exact: true }).click();
    await expect(dialog).toContainText("0000-0002-1825-0097");

    await page.getByRole("button", { name: "Apply Selected ORCID", exact: true }).click();
    await expect(dialog).toBeHidden();
    await expect(lookupButton).toBeFocused();

    await expect(firstCreatorRow.locator('input[name*="[identifier]"]')).toHaveValue("0000-0002-1825-0097");

    await lookupButton.click();
    await expect(dialog).toBeVisible();
    await page.keyboard.press("Escape");
    await expect(dialog).toBeHidden();
    await expect(lookupButton).toBeFocused();
  });

  test("persists creator reorder after save and edit reload", async ({ page }) => {
    await signInWithDeveloperAuth(page);
    await createDatasetAndOpenEdit(page);

    const creatorRows = page.locator("#creator-rows .idb-nested-row");

    await fillIndividualCreatorRow(page, 0, {
      familyName: "Alpha",
      givenName: "Ann",
      email: "alpha@example.test",
    });
    await addCreatorRowFromToolbar(page);
    await expect(creatorRows).toHaveCount(2);
    await fillIndividualCreatorRow(page, 1, {
      familyName: "Beta",
      givenName: "Ben",
      email: "beta@example.test",
    });
    await selectPrimaryContact(page, 0);

    await creatorRows.nth(1).locator('button[data-action="deposit-form#moveRowUp"]').click();
    await page.getByRole("button", { name: "Save & Continue", exact: true }).click();
    await expect(page).toHaveURL(/\/datasets\/[^/]+$/);
    await page.getByRole("link", { name: "Edit Dataset", exact: true }).click();
    await expect(page).toHaveURL(/\/datasets\/.*\/edit$/);

    const reloadedRows = page.locator("#creator-rows .idb-nested-row");
    await expect(reloadedRows).toHaveCount(2);
    await expect(reloadedRows.nth(0).locator('input[name*="[family_name]"]')).toHaveValue("Beta");
    await expect(reloadedRows.nth(1).locator('input[name*="[family_name]"]')).toHaveValue("Alpha");
    await expect(reloadedRows.nth(0).locator('input[name*="[row_position]"]')).toHaveValue("1");
    await expect(reloadedRows.nth(1).locator('input[name*="[row_position]"]')).toHaveValue("2");
  });

  test("collapses core metadata grid to one column on mobile", async ({ page }) => {
    await signInWithDeveloperAuth(page);
    await page.setViewportSize({ width: 390, height: 844 });
    await createDatasetAndOpenEdit(page);

    const grid = page.locator("#dataset-core-metadata .idb-metadata-grid").first();
    await expect(grid).toBeVisible();

    const gridColumnCount = await grid.evaluate((el) => getComputedStyle(el).gridTemplateColumns.split(" ").filter(Boolean).length);
    expect(gridColumnCount).toBe(1);

    const titleField = page.locator('input[name="dataset[title]"]');
    const licenseField = page.locator('select[name="dataset[license]"]');
    const titleBox = await titleField.boundingBox();
    const licenseBox = await licenseField.boundingBox();

    expect(titleBox).not.toBeNull();
    expect(licenseBox).not.toBeNull();
    expect(licenseBox.y).toBeGreaterThan(titleBox.y + 10);
  });

  test("switches between individual and organization creator modes with destructive cleanup", async ({ page }) => {
    await signInWithDeveloperAuthRole(page, "admin");
    await createDatasetAndOpenEdit(page);
    await page.locator('input[name="dataset[identifier]"]').fill(`10.5555/SWITCH-${Date.now()}`);

    const creatorRows = page.locator("#creator-rows .idb-nested-row");
    await fillIndividualCreatorRow(page, 0, {
      familyName: "Alpha",
      givenName: "Ann",
      email: "alpha-switch@example.test",
    });
    await addCreatorRowFromToolbar(page);
    await expect(creatorRows).toHaveCount(2);
    await fillIndividualCreatorRow(page, 1, {
      familyName: "Beta",
      givenName: "Ben",
      email: "beta-switch@example.test",
    });
    await selectPrimaryContact(page, 0);

    await page.getByRole("button", { name: "Use Organization Creators", exact: true }).click();
    await expect(page).toHaveURL(/\/datasets\/[^/]+$/);
    await page.getByRole("link", { name: "Edit Dataset", exact: true }).click();
    await expect(page).toHaveURL(/\/datasets\/.*\/edit$/);

    await expect(page.locator("#dataset-creators")).toContainText("Organization Name(s)");
    await expect(page.locator('input[name*="[family_name]"]')).toHaveCount(0);
    await expect(page.locator('input[name*="[given_name]"]')).toHaveCount(0);
    await expect(page.locator('#creator-rows input[name*="[identifier]"]')).toHaveCount(0);

    const orgRows = page.locator("#creator-rows .idb-nested-row");
    await expect(orgRows).toHaveCount(1);
    await fillOrganizationCreatorRow(page, 0, {
      institutionName: "Org Alpha",
      email: "org-alpha@example.test",
    });
    await addCreatorRowFromToolbar(page);
    await expect(orgRows).toHaveCount(2);
    await fillOrganizationCreatorRow(page, 1, {
      institutionName: "Org Beta",
      email: "org-beta@example.test",
    });
    await selectPrimaryContact(page, 0);

    await page.getByRole("button", { name: "Use Individual Creators", exact: true }).click();
    await expect(page).toHaveURL(/\/datasets\/[^/]+$/);
    await page.getByRole("link", { name: "Edit Dataset", exact: true }).click();
    await expect(page).toHaveURL(/\/datasets\/.*\/edit$/);

    await expect(page.locator("#dataset-creators")).toContainText("Family Name(s)");
    await expect(page.locator('input[name*="[institution_name]"]')).toHaveCount(0);
    await expect(page.locator('input[name*="[family_name]"]')).toHaveCount(1);
  });
});
