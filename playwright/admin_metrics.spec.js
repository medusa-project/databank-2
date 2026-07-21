const fs = require("node:fs/promises");
const path = require("node:path");
const { test, expect } = require("@playwright/test");

const DATASETS_TSV_KEY = "datasets_tsv";
const FUNDERS_CSV_KEY = "funders_csv";

const datasetTsvLockPath = path.join(
  process.cwd(),
  "public",
  "datasets.tsv.lock",
);
const fundersCsvLockPath = path.join(
  process.cwd(),
  "public",
  "funders.csv.lock",
);

async function clearLock(lockPath) {
  try {
    await fs.unlink(lockPath);
  } catch (error) {
    if (error.code !== "ENOENT") {
      throw error;
    }
  }
}

async function markInProgress(lockPath) {
  await fs.writeFile(lockPath, "", { flag: "a" });
}

async function signInAs(page, role) {
  const response = await page.request.post("/auth/developer/callback", {
    form: { email: `test-${role}@example.test`, name: `Test ${role}`, role },
  });
  expect(response.ok()).toBeTruthy();
}

test.describe("admin metrics refresh flow", () => {
  test.beforeEach(async ({ page }) => {
    await signInAs(page, "admin");
    await Promise.all([
      clearLock(datasetTsvLockPath),
      clearLock(fundersCsvLockPath),
    ]);
  });

  test.afterEach(async () => {
    await Promise.all([
      clearLock(datasetTsvLockPath),
      clearLock(fundersCsvLockPath),
    ]);
  });

  test("starting a metric refresh hides its download action and shows the metric-specific in-progress state", async ({
    page,
  }) => {
    await page.goto("/admin_metrics");

    const metricCard = page.getByTestId(`metric-card-${DATASETS_TSV_KEY}`);

    await expect(
      metricCard.getByRole("heading", { name: "Datasets TSV" }),
    ).toBeVisible();
    await expect(
      metricCard.getByTestId(`metric-download-${DATASETS_TSV_KEY}`),
    ).toBeVisible();
    await expect(
      metricCard.getByTestId(`metric-refresh-${DATASETS_TSV_KEY}`),
    ).toBeVisible();

    await Promise.all([
      page.waitForLoadState("networkidle"),
      metricCard.getByTestId(`metric-refresh-${DATASETS_TSV_KEY}`).click(),
    ]);

    await expect(page.locator("body")).toContainText(
      "Datasets TSV refresh started.",
    );
    await expect(
      metricCard.getByTestId(`metric-refresh-status-${DATASETS_TSV_KEY}`),
    ).toContainText("refresh in progress");
    await expect(
      metricCard.getByTestId(`metric-download-${DATASETS_TSV_KEY}`),
    ).toHaveCount(0);
    await expect(
      metricCard.getByTestId(`metric-refresh-${DATASETS_TSV_KEY}`),
    ).toHaveCount(0);
  });

  test("an in-progress metric is called out by name without hiding actions for other metrics", async ({
    page,
  }) => {
    await markInProgress(fundersCsvLockPath);

    await page.goto("/admin_metrics");

    const inProgressCard = page.getByTestId(`metric-card-${FUNDERS_CSV_KEY}`);
    const unaffectedCard = page.getByTestId(`metric-card-${DATASETS_TSV_KEY}`);

    await expect(
      inProgressCard.getByTestId(`metric-refresh-status-${FUNDERS_CSV_KEY}`),
    ).toContainText("refresh in progress");
    await expect(
      inProgressCard.getByTestId(`metric-download-${FUNDERS_CSV_KEY}`),
    ).toHaveCount(0);
    await expect(
      inProgressCard.getByTestId(`metric-refresh-${FUNDERS_CSV_KEY}`),
    ).toHaveCount(0);

    await expect(
      unaffectedCard.getByTestId(`metric-download-${DATASETS_TSV_KEY}`),
    ).toBeVisible();
    await expect(
      unaffectedCard.getByTestId(`metric-refresh-${DATASETS_TSV_KEY}`),
    ).toBeVisible();
  });
});

test.describe("curator metrics view access", () => {
  test.beforeEach(async ({ page }) => {
    await signInAs(page, "curator");
  });

  test("curator can view the admin metrics page but sees no refresh buttons", async ({
    page,
  }) => {
    await page.goto("/admin_metrics");

    await expect(
      page.getByRole("heading", { name: "Curator Metrics" }),
    ).toBeVisible();

    await expect(
      page.locator(
        "[data-testid^='metric-refresh-']:not([data-testid*='status'])",
      ),
    ).toHaveCount(0);
  });
});
