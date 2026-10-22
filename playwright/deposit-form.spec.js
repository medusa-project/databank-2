const { test, expect } = require("@playwright/test");
const AxeBuilder = require("@axe-core/playwright").default;

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
  await page.locator("#owner-yes").check();
  await page.locator("#private-yes").check();
  await page.locator("#agree-yes").check();
  await page.getByRole("button", { name: "Submit", exact: true }).click();
  await expect(page).toHaveURL(/\/datasets\/.*\/edit$/);

  await page
    .locator('input[name="dataset[title]"]')
    .fill(`Deposit Form Dataset ${Date.now()}`);
  await page.locator('select[name="dataset[license]"]').selectOption("CC0");
}

async function addCreatorRowFromToolbar(page) {
  await page
    .locator('button[data-action="deposit-form#addCreatorRow"]')
    .click();
}

async function fillIndividualCreatorRow(
  page,
  index,
  { familyName, givenName, email },
) {
  const row = page.locator("#creator-rows .idb-nested-row").nth(index);
  await row.locator('input[name*="[family_name]"]').fill(familyName);
  await row.locator('input[name*="[given_name]"]').fill(givenName);
  await row.locator('input[name*="[email]"]').fill(email);
}

async function fillOrganizationCreatorRow(
  page,
  index,
  { institutionName, email },
) {
  const row = page.locator("#creator-rows .idb-nested-row").nth(index);
  await row.locator('input[name*="[institution_name]"]').fill(institutionName);
  await row.locator('input[name*="[email]"]').fill(email);
}

async function selectPrimaryContact(page, index = 0) {
  await page
    .locator('#creator-rows input[type="radio"][name="primary_contact_index"]')
    .nth(index)
    .check();
}

test.describe("deposit form parity behavior", () => {
  test("submits draft workflow actions by keyboard and keeps deletion independent", async ({ page }) => {
    await signInWithDeveloperAuth(page);
    await createDatasetAndOpenEdit(page);
    const editPath = new URL(page.url()).pathname;
    const showPath = editPath.replace(/\/edit$/, "");

    await expect.poll(() => page.locator("#dataset-edit-form").evaluate((form) =>
      Boolean(window.Stimulus?.getControllerForElementAndIdentifier(form, "deposit-form")),
    )).toBe(true);
    await fillIndividualCreatorRow(page, 0, {
      familyName: "Workflow",
      givenName: "Tester",
      email: "workflow@example.test",
    });
    await selectPrimaryContact(page);
    const title = `Workflow save ${Date.now()}`;
    await page.locator('input[name="dataset[title]"]').fill(title);
    const save = page.getByRole("button", { name: "Save & Continue", exact: true });
    await save.focus();
    await page.keyboard.press("Enter");
    await expect(page).toHaveURL(new RegExp(`${showPath}$`));

    await page.goto(editPath);
    await expect(page.locator('input[name="dataset[title]"]')).toHaveValue(title);
    await page.locator('input[name="dataset[title]"]').fill(`${title} exit`);
    await selectPrimaryContact(page);
    const exit = page.getByRole("button", { name: "Save & Exit", exact: true });
    await exit.focus();
    await page.keyboard.press("Enter");
    await expect(page).toHaveURL(/\/datasets$/);

    await page.goto(editPath);
    await expect(page.locator('input[name="dataset[title]"]')).toHaveValue(`${title} exit`);
    const remove = page.getByRole("button", { name: "Delete", exact: true });
    await expect(remove).toHaveAttribute("form", "dataset-delete-form");
  });

  test("labels individual creator fields in initial and added rows", async ({ page }) => {
    await signInWithDeveloperAuth(page);
    await createDatasetAndOpenEdit(page);
    await addCreatorRowFromToolbar(page);

    const rows = page.locator("#creator-rows .idb-nested-row");
    await expect(rows).toHaveCount(2);
    for (const row of await rows.all()) {
      for (const name of ["Family Name(s)", "Given Name(s)", "ORCID", "Email"]) {
        const field = row.getByLabel(name, { exact: false });
        await expect(field).toHaveCount(1);
        await expect(field).toHaveAccessibleName(new RegExp(`^${name.replace(/[()]/g, "\\$&")}\\s*\\*?$`));
      }
    }
    const results = await new AxeBuilder({ page }).include("main").analyze();
    expect(results.violations).toEqual([]);
  });

  test("labels organization creator fields in initial and added rows", async ({ page }) => {
    await signInWithDeveloperAuthRole(page, "admin");
    await createDatasetAndOpenEdit(page);
    await page.locator("#dataset-curation summary").click();
    await page.locator("#dataset_identifier").fill(`10.5555/LABELS-${Date.now()}`);
    await fillIndividualCreatorRow(page, 0, {
      familyName: "Smith", givenName: "Jean", email: "jean@example.test",
    });
    await selectPrimaryContact(page);
    await page.getByRole("button", { name: "Use Organization Creators" }).click();
    await expect(page).toHaveURL(/\/datasets\/[^/]+$/);
    await page.getByRole("link", { name: "Edit Dataset", exact: true }).click();
    await expect(page.locator('#creator-rows input[name*="[institution_name]"]')).toBeVisible();
    await expect(page.locator("#dataset_org_creators")).toHaveValue("true");
    await addCreatorRowFromToolbar(page);

    const rows = page.locator("#creator-rows .idb-nested-row");
    await expect(rows).toHaveCount(2);
    for (const row of await rows.all()) {
      for (const name of ["Organization Name(s)", "Email"]) {
        const field = row.getByLabel(name, { exact: false });
        await expect(field).toHaveCount(1);
        await expect(field).toHaveAccessibleName(new RegExp(`^${name.replace(/[()]/g, "\\$&")}\\s*\\*?$`));
      }
    }
    for (const disclosure of await page.locator("main details.idb-section-disclosure").all()) {
      if (await disclosure.getAttribute("open") === null) {
        await disclosure.locator(":scope > summary").click();
      }
    }
    const results = await new AxeBuilder({ page }).include("main").analyze();
    expect(results.violations).toEqual([]);
  });

  test("keeps keyboard focus usable when adding, reordering, and removing creators", async ({ page }) => {
    await signInWithDeveloperAuth(page);
    await createDatasetAndOpenEdit(page);
    const add = page.getByRole("button", { name: "Add author row", exact: true });
    await add.focus();
    await page.keyboard.press("Enter");
    const rows = page.locator("#creator-rows .idb-nested-row");
    await expect(rows.nth(1).getByLabel("Family Name(s)")).toBeFocused();
    const up = rows.nth(1).getByRole("button", { name: "Move author row up" });
    await up.focus();
    await page.keyboard.press("Enter");
    await expect(rows.nth(0).getByRole("button", { name: "Move author row up" })).toBeFocused();
    await rows.nth(0).getByRole("button", { name: "Remove author row" }).focus();
    await page.keyboard.press("Enter");
    await expect(rows.nth(0).getByLabel("Family Name(s)")).toBeFocused();
    await rows.nth(0).getByRole("button", { name: "Remove author row" }).focus();
    await page.keyboard.press("Enter");
    await expect(add).toBeFocused();
  });

  test("keeps access grants separate from dataset editing and submits them independently", async ({ page }) => {
    await signInWithDeveloperAuthRole(page, "admin");
    await createDatasetAndOpenEdit(page);
    await page.locator("#dataset-curation summary").click();
    const email = page.getByLabel("Grant recipient email");
    expect(await email.evaluate((field) => field.form.id)).toBe("dataset-access-grant-form");
    expect(await page.locator("#dataset_title").evaluate((field) => field.form.id)).toBe("dataset-edit-form");
    expect(await page.locator("#dataset_description").evaluate((field) => field.form.id)).toBe("dataset-edit-form");
    const recipient = `reviewer-${Date.now()}@example.test`;
    await email.fill(recipient);
    await page.getByRole("button", { name: "Grant Access", exact: true }).click();
    await expect(page.getByText("Dataset access grant added.", { exact: true })).toBeVisible();
    await page.locator("#dataset-curation summary").click();
    await expect(page.getByRole("cell", { name: recipient, exact: true })).toBeVisible();
    const remove = page.getByRole("button", { name: `Remove access for ${recipient}`, exact: true });
    page.once("dialog", (dialog) => dialog.accept());
    await remove.click();
    await expect(page.getByText("Dataset access grant removed.", { exact: true })).toBeVisible();
    await page.locator("#dataset-curation summary").click();
    await expect(page.getByRole("cell", { name: recipient, exact: true })).toHaveCount(0);
  });

  test("opens the file chooser through a keyboard-operable button", async ({ page }) => {
    await signInWithDeveloperAuth(page);
    await createDatasetAndOpenEdit(page);
    await expect(page.locator('input[type="file"]')).toHaveAttribute("aria-label", "Select files from your computer");
    await expect.poll(() => page.locator(".idb-file-upload-section").evaluate(
      (element) => !!window.Stimulus?.getControllerForElementAndIdentifier(element, "file-upload"),
    )).toBe(true);
    await page.getByRole("button", { name: "Select files from your computer" }).focus();
    const chooser = page.waitForEvent("filechooser");
    await page.keyboard.press("Enter");
    await chooser;
  });

  test("submits file actions independently without validating unsaved creator fields", async ({ page }) => {
    await signInWithDeveloperAuth(page);
    await createDatasetAndOpenEdit(page);
    await page.locator('input[type="file"]').setInputFiles([
      { name: "first.csv", mimeType: "text/csv", buffer: Buffer.from("value\n1\n") },
      { name: "second.csv", mimeType: "text/csv", buffer: Buffer.from("value\n2\n") },
      { name: "third.csv", mimeType: "text/csv", buffer: Buffer.from("value\n3\n") },
    ]);
    await expect(page.getByRole("button", { name: "Delete first.csv", exact: true })).toBeVisible();
    await page.getByRole("button", { name: "Delete first.csv", exact: true }).click();
    await expect(page.getByRole("button", { name: "Delete first.csv", exact: true })).toHaveCount(0);
    await page.getByRole("checkbox", { name: "Select all files", exact: true }).check();
    page.once("dialog", (dialog) => dialog.accept());
    await page.getByRole("button", { name: /Delete Selected/ }).click();
    await expect(page.locator("#datafiles")).toHaveCount(0);
    await expect(page.locator("#dataset_description")).toBeVisible();
  });

  test("reorders creator rows and updates persisted row positions", async ({
    page,
  }) => {
    await signInWithDeveloperAuth(page);
    await createDatasetAndOpenEdit(page);

    const creatorRows = page.locator("#creator-rows .idb-nested-row");

    await creatorRows
      .nth(0)
      .locator('input[name*="[family_name]"]')
      .fill("Alpha");
    await addCreatorRowFromToolbar(page);
    await expect(creatorRows).toHaveCount(2);
    await creatorRows
      .nth(1)
      .locator('input[name*="[family_name]"]')
      .fill("Beta");

    await creatorRows
      .nth(1)
      .locator('button[data-action="deposit-form#moveRowUp"]')
      .click();

    await expect(
      creatorRows.nth(0).locator('input[name*="[family_name]"]'),
    ).toHaveValue("Beta");
    await expect(
      creatorRows.nth(1).locator('input[name*="[family_name]"]'),
    ).toHaveValue("Alpha");

    await expect(
      creatorRows.nth(0).locator('input[name*="[row_position]"]'),
    ).toHaveValue("1");
    await expect(
      creatorRows.nth(1).locator('input[name*="[row_position]"]'),
    ).toHaveValue("2");
  });

  test("supports ORCID lookup dialog with focus restore and field application", async ({
    page,
  }) => {
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

    const firstCreatorRow = page
      .locator("#creator-rows .idb-nested-row")
      .first();
    const lookupButton = firstCreatorRow.getByRole("button", {
      name: "Look Up ORCID",
      exact: true,
    });

    await firstCreatorRow
      .locator('input[name*="[family_name]"]')
      .fill("Lovelace");
    await firstCreatorRow.locator('input[name*="[given_name]"]').fill("Ada");

    await lookupButton.click();

    const dialog = page.locator("#orcid-lookup-dialog");
    await expect(dialog).toBeVisible();
    await expect(page.locator("#orcid-family-name")).toBeFocused();

    await page.getByRole("button", { name: "Search", exact: true }).click();
    await expect(dialog).toContainText("0000-0002-1825-0097");

    await page
      .getByRole("button", { name: "Apply Selected ORCID", exact: true })
      .click();
    await expect(dialog).toBeHidden();
    await expect(lookupButton).toBeFocused();

    await expect(
      firstCreatorRow.locator('input[name*="[identifier]"]'),
    ).toHaveValue("0000-0002-1825-0097");

    await lookupButton.click();
    await expect(dialog).toBeVisible();
    await page.keyboard.press("Escape");
    await expect(dialog).toBeHidden();
    await expect(lookupButton).toBeFocused();
  });

  test("applies ORCID names containing apostrophes", async ({ page }) => {
    await signInWithDeveloperAuth(page);

    await page.route("**/datasets/*/creators/orcid_lookup**", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          results: [
            {
              orcid: "0000-0002-1825-0098",
              family_name: "O'Keefe",
              given_name: "D'Arcy",
              institution: "O'Brien Institute",
            },
          ],
        }),
      });
    });

    await createDatasetAndOpenEdit(page);

    const firstCreatorRow = page
      .locator("#creator-rows .idb-nested-row")
      .first();
    const lookupButton = firstCreatorRow.getByRole("button", {
      name: "Look Up ORCID",
      exact: true,
    });

    await firstCreatorRow
      .locator('input[name*="[family_name]"]')
      .fill("O'Keefe");
    await lookupButton.click();

    const dialog = page.locator("#orcid-lookup-dialog");
    await expect(dialog).toBeVisible();

    await page.getByRole("button", { name: "Search", exact: true }).click();
    await expect(dialog).toContainText("O'Keefe");
    await expect(dialog).toContainText("O'Brien Institute");

    await page
      .getByRole("button", { name: "Apply Selected ORCID", exact: true })
      .click();
    await expect(dialog).toBeHidden();

    await expect(
      firstCreatorRow.locator('input[name*="[family_name]"]'),
    ).toHaveValue("O'Keefe");
    await expect(
      firstCreatorRow.locator('input[name*="[given_name]"]'),
    ).toHaveValue("D'Arcy");
    await expect(
      firstCreatorRow.locator('input[name*="[identifier]"]'),
    ).toHaveValue("0000-0002-1825-0098");
  });

  test("persists creator reorder after save and edit reload", async ({
    page,
  }) => {
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

    await creatorRows
      .nth(1)
      .locator('button[data-action="deposit-form#moveRowUp"]')
      .click();
    await page
      .getByRole("button", { name: "Save & Continue", exact: true })
      .click();
    await expect(page).toHaveURL(/\/datasets\/[^/]+$/);
    await page.getByRole("link", { name: "Edit Dataset", exact: true }).click();
    await expect(page).toHaveURL(/\/datasets\/.*\/edit$/);

    const reloadedRows = page.locator("#creator-rows .idb-nested-row");
    await expect(reloadedRows).toHaveCount(2);
    await expect(
      reloadedRows.nth(0).locator('input[name*="[family_name]"]'),
    ).toHaveValue("Beta");
    await expect(
      reloadedRows.nth(1).locator('input[name*="[family_name]"]'),
    ).toHaveValue("Alpha");
    await expect(
      reloadedRows.nth(0).locator('input[name*="[row_position]"]'),
    ).toHaveValue("1");
    await expect(
      reloadedRows.nth(1).locator('input[name*="[row_position]"]'),
    ).toHaveValue("2");
  });

  test("collapses core metadata grid to one column on mobile", async ({
    page,
  }) => {
    await signInWithDeveloperAuth(page);
    await page.setViewportSize({ width: 390, height: 844 });
    await createDatasetAndOpenEdit(page);

    const grid = page
      .locator("#dataset-description .idb-metadata-grid")
      .first();
    await expect(grid).toBeVisible();

    const gridColumnCount = await grid.evaluate(
      (el) =>
        getComputedStyle(el).gridTemplateColumns.split(" ").filter(Boolean)
          .length,
    );
    expect(gridColumnCount).toBe(1);

    const titleField = page.locator('input[name="dataset[title]"]');
    const licenseField = page.locator('select[name="dataset[license]"]');
    const titleBox = await titleField.boundingBox();
    const licenseBox = await licenseField.boundingBox();

    expect(titleBox).not.toBeNull();
    expect(licenseBox).not.toBeNull();
    expect(licenseBox.y).toBeGreaterThan(titleBox.y + 10);
  });

  test("switches between individual and organization creator modes with destructive cleanup", async ({
    page,
  }) => {
    await signInWithDeveloperAuthRole(page, "admin");
    await createDatasetAndOpenEdit(page);
    await page.locator("#dataset-curation summary").click();
    await page
      .locator('input[name="dataset[identifier]"]')
      .fill(`10.5555/SWITCH-${Date.now()}`);

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

    await page
      .getByRole("button", { name: "Use Organization Creators", exact: true })
      .click();
    await expect(page).toHaveURL(/\/datasets\/[^/]+$/);
    await page.getByRole("link", { name: "Edit Dataset", exact: true }).click();
    await expect(page).toHaveURL(/\/datasets\/.*\/edit$/);

    await expect(page.locator("#dataset-creators")).toContainText(
      "Organization Name(s)",
    );
    await expect(page.locator('input[name*="[family_name]"]')).toHaveCount(0);
    await expect(page.locator('input[name*="[given_name]"]')).toHaveCount(0);
    await expect(
      page.locator('#creator-rows input[name*="[identifier]"]'),
    ).toHaveCount(0);

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

    await page
      .getByRole("button", { name: "Use Individual Creators", exact: true })
      .click();
    await expect(page).toHaveURL(/\/datasets\/[^/]+$/);
    await page.getByRole("link", { name: "Edit Dataset", exact: true }).click();
    await expect(page).toHaveURL(/\/datasets\/.*\/edit$/);

    await expect(page.locator("#dataset-creators")).toContainText(
      "Family Name(s)",
    );
    await expect(page.locator('input[name*="[institution_name]"]')).toHaveCount(
      0,
    );
    await expect(page.locator('input[name*="[family_name]"]')).toHaveCount(1);
  });
});
