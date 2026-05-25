const { test, expect } = require("@playwright/test");
const AxeBuilder = require("@axe-core/playwright").default;
const { DATASETS } = require("./fixtures/index.js");

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

async function scanPage(page, path) {
  await page.goto(path);
  return new AxeBuilder({ page }).include("main").analyze();
}

async function expectNoA11yViolations(page, path) {
  const results = await scanPage(page, path);
  expect(
    results.violations,
    `Accessibility violations on ${path}:\n${JSON.stringify(results.violations, null, 2)}`,
  ).toEqual([]);
}

async function signInAs(page, role) {
  const response = await page.request.post("/auth/developer/callback", {
    form: {
      email: `a11y-${role}@example.test`,
      name: `A11y ${role}`,
      role,
    },
  });
  expect(response.ok()).toBeTruthy();
}

async function createDataset(page) {
  await page.goto("/datasets/new");
  await page.locator('input[name="dataset[title]"]').fill(`A11y Dataset ${Date.now()}`);
  await page.getByRole("button", { name: "Create Dataset", exact: true }).click();
  await expect(page).toHaveURL(/\/datasets\//);
  return page.url();
}

async function createGuideSection(page) {
  await page.goto("/guide/sections/new");
  await page.locator('input[name="guide_section[label]"]').fill(`A11y Section ${Date.now()}`);
  await page.locator('input[name="guide_section[anchor]"]').fill(`a11y-section-${Date.now()}`);
  await page.getByRole("button", { name: "Save Section" }).click();
  await expect(page).toHaveURL(/\/guide\/sections/);
  const editLink = page.locator('a[href*="/guide/sections/"][href*="/edit"]').last();
  return editLink.getAttribute("href");
}

async function createGuideItem(page, sectionEditHref) {
  // Derive section id from its edit path  (/guide/sections/42/edit → 42)
  const sectionId = sectionEditHref.match(/\/guide\/sections\/(\d+)\/edit/)?.[1];
  await page.goto("/guide/items/new");
  await page.locator('select[name="guide_item[section_id]"]').selectOption(sectionId);
  await page.locator('input[name="guide_item[label]"]').fill(`A11y Item ${Date.now()}`);
  await page.locator('input[name="guide_item[anchor]"]').fill(`a11y-item-${Date.now()}`);
  await page.getByRole("button", { name: "Save Item" }).click();
  await expect(page).toHaveURL(/\/guide\/items/);
  const editLink = page.locator('a[href*="/guide/items/"][href*="/edit"]').last();
  return editLink.getAttribute("href");
}

async function createGuideSubitem(page, itemEditHref) {
  const itemId = itemEditHref.match(/\/guide\/items\/(\d+)\/edit/)?.[1];
  await page.goto("/guide/subitems/new");
  await page.locator('select[name="guide_subitem[item_id]"]').selectOption(itemId);
  await page.locator('input[name="guide_subitem[label]"]').fill(`A11y Subitem ${Date.now()}`);
  await page.locator('input[name="guide_subitem[anchor]"]').fill(`a11y-subitem-${Date.now()}`);
  await page.getByRole("button", { name: "Save Subitem" }).click();
  await expect(page).toHaveURL(/\/guide\/subitems/);
  const editLink = page.locator('a[href*="/guide/subitems/"][href*="/edit"]').last();
  return editLink.getAttribute("href");
}

// ---------------------------------------------------------------------------
// Public pages — no auth required
// ---------------------------------------------------------------------------

test.describe("public pages", () => {
  test("home page", async ({ page }) => {
    await expectNoA11yViolations(page, "/");
  });

  test("login page", async ({ page }) => {
    await expectNoA11yViolations(page, "/login");
  });

  test("datasets index", async ({ page }) => {
    await expectNoA11yViolations(page, "/datasets");
  });

  test("dataset show — released fixture", async ({ page }) => {
    await expectNoA11yViolations(page, `/datasets/${DATASETS.RELEASED_A}`);
  });

  test("dataset show — second released fixture", async ({ page }) => {
    await expectNoA11yViolations(page, `/datasets/${DATASETS.RELEASED_B}`);
  });

  test("policies page", async ({ page }) => {
    await expectNoA11yViolations(page, "/policies");
  });

  test("guides page", async ({ page }) => {
    await expectNoA11yViolations(page, "/guides");
  });

  test("contact page", async ({ page }) => {
    await expectNoA11yViolations(page, "/contact");
  });

  test("404 page", async ({ page }) => {
    await expectNoA11yViolations(page, "/this-page-does-not-exist");
  });
});

// ---------------------------------------------------------------------------
// Depositor pages — authenticated as depositor
// ---------------------------------------------------------------------------

test.describe("depositor pages", () => {
  test.beforeEach(async ({ page }) => {
    await signInAs(page, "depositor");
  });

  test("pre-deposit considerations", async ({ page }) => {
    await expectNoA11yViolations(page, "/datasets/pre_deposit");
  });

  test("new dataset form", async ({ page }) => {
    await expectNoA11yViolations(page, "/datasets/new");
  });

  test("dataset show after create", async ({ page }) => {
    const url = await createDataset(page);
    const results = await new AxeBuilder({ page }).include("main").analyze();
    expect(
      results.violations,
      `Violations on dataset show: ${JSON.stringify(results.violations, null, 2)}`,
    ).toEqual([]);
  });

  test("dataset edit form", async ({ page }) => {
    const url = await createDataset(page);
    const key = url.match(/\/datasets\/([^/]+)/)?.[1];
    await expectNoA11yViolations(page, `/datasets/${key}/edit`);
  });

  test("dataset pre-version page", async ({ page }) => {
    const url = await createDataset(page);
    const key = url.match(/\/datasets\/([^/]+)/)?.[1];
    await expectNoA11yViolations(page, `/datasets/${key}/pre_version`);
  });

  test("dataset version controls page", async ({ page }) => {
    const url = await createDataset(page);
    const key = url.match(/\/datasets\/([^/]+)/)?.[1];
    await expectNoA11yViolations(page, `/datasets/${key}/version_controls`);
  });
});

// ---------------------------------------------------------------------------
// Admin pages — authenticated as admin
// ---------------------------------------------------------------------------

test.describe("admin pages", () => {
  test.beforeEach(async ({ page }) => {
    await signInAs(page, "admin");
  });

  test("external delivery attempts", async ({ page }) => {
    await expectNoA11yViolations(page, "/admin/external_delivery_attempts");
  });

  // Guide sections CMS
  test("guide sections index", async ({ page }) => {
    await expectNoA11yViolations(page, "/guide/sections");
  });

  test("guide sections new form", async ({ page }) => {
    await expectNoA11yViolations(page, "/guide/sections/new");
  });

  test("guide sections edit form", async ({ page }) => {
    const editHref = await createGuideSection(page);
    await expectNoA11yViolations(page, editHref);
  });

  // Guide items CMS
  test("guide items index", async ({ page }) => {
    await expectNoA11yViolations(page, "/guide/items");
  });

  test("guide items new form", async ({ page }) => {
    // Ensure a section exists so the select is populated
    await createGuideSection(page);
    await expectNoA11yViolations(page, "/guide/items/new");
  });

  test("guide items edit form", async ({ page }) => {
    const sectionHref = await createGuideSection(page);
    const itemHref = await createGuideItem(page, sectionHref);
    await expectNoA11yViolations(page, itemHref);
  });

  // Guide subitems CMS
  test("guide subitems index", async ({ page }) => {
    await expectNoA11yViolations(page, "/guide/subitems");
  });

  test("guide subitems new form", async ({ page }) => {
    // Ensure an item exists so the select is populated
    const sectionHref = await createGuideSection(page);
    await createGuideItem(page, sectionHref);
    await expectNoA11yViolations(page, "/guide/subitems/new");
  });

  test("guide subitems edit form", async ({ page }) => {
    const sectionHref = await createGuideSection(page);
    const itemHref = await createGuideItem(page, sectionHref);
    const subitemHref = await createGuideSubitem(page, itemHref);
    await expectNoA11yViolations(page, subitemHref);
  });
});
