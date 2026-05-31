const { test, expect } = require("@playwright/test");
const { execSync } = require("child_process");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");

function signInAs(page, { email, name, role }) {
  return page.request.post("/auth/developer/callback", {
    form: { email, name, role },
  });
}

function railsRunnerJson(script) {
  const escaped = script.replace(/'/g, "'\\''");
  const command = `RAILS_ENV=test bundle exec rails runner '${escaped}'`;
  const output = execSync(command, { cwd: ROOT, encoding: "utf8" }).trim();
  return JSON.parse(output);
}

function seedPublishedMetadataEmbargoDataset() {
  return railsRunnerJson(`
    require "json"
    require "securerandom"

    dataset = Dataset.create!(
      title: "E2E Metadata Embargo Source #{Time.now.to_i}",
      description: "Published source dataset for e2e version workflow",
      keywords: "e2e,embargo",
      subject: "Earth Systems",
      license: "CC0",
      publisher: "Illinois Data Bank",
      owner_uid: "owner-e2e",
      depositor_name: "Owner E2E",
      depositor_email: "owner-e2e@example.test",
      publication_state: :published,
      identifier: "10.5555/IDB-E2E-#{SecureRandom.hex(4)}",
      embargo: Dataset::EMBARGO_METADATA,
      release_date: Date.current + 30
    )

    dataset.creators.create!(
      name: "Owner E2E",
      email: "owner-e2e@example.test",
      contact: true,
      position: 1
    )

    puts({ key: dataset.key }.to_json)
  `);
}

test.describe("embargo versioning parity", () => {
  test("depositor requests new version and curator approval creates unembargoed draft", async ({ page }) => {
    const seeded = seedPublishedMetadataEmbargoDataset();

    const ownerLogin = await signInAs(page, {
      email: "owner-e2e@example.test",
      name: "Owner E2E",
      role: "depositor",
    });
    expect(ownerLogin.ok()).toBeTruthy();

    await page.goto(`/datasets/${seeded.key}`);
    await expect(page.getByRole("link", { name: "Request New Version", exact: true })).toBeVisible();

    await page.getByRole("link", { name: "Request New Version", exact: true }).click();
    await expect(page).toHaveURL(new RegExp(`/datasets/${seeded.key}/pre_version$`));

    await page.locator("textarea[name='comment']").fill("Need to publish corrected files.");
    await page.getByRole("button", { name: "Request New Version", exact: true }).click();

    await expect(page).toHaveURL(new RegExp(`/datasets/${seeded.key}/version_acknowledge`));
    await expect(page.getByRole("heading", { name: "Your new version request has been submitted" })).toBeVisible();

    const curatorLogin = await signInAs(page, {
      email: "curator-e2e@example.test",
      name: "Curator E2E",
      role: "curator",
    });
    expect(curatorLogin.ok()).toBeTruthy();

    await page.goto(`/datasets/${seeded.key}/version_controls`);
    await expect(page.getByRole("heading", { name: "Pending Version Requests" })).toBeVisible();

    await page.locator("textarea[name='review_note']").first().fill("Approved by curator in e2e parity test.");
    await page.getByRole("button", { name: "Approve and Create Draft", exact: true }).click();

    await expect(page).toHaveURL(new RegExp(`/datasets/${seeded.key}/version_controls$`));
    await expect(page.getByText("Version request approved. Draft")).toBeVisible();

    const draftLink = page.getByRole("link", { name: /Draft created:/ }).first();
    await expect(draftLink).toBeVisible();

    const draftPath = await draftLink.getAttribute("href");
    expect(draftPath).toBeTruthy();

    const ownerReturnLogin = await signInAs(page, {
      email: "owner-e2e@example.test",
      name: "Owner E2E",
      role: "depositor",
    });
    expect(ownerReturnLogin.ok()).toBeTruthy();

    await page.goto(draftPath);

    await expect(page).toHaveURL(/\/datasets\/[^/]+\/edit$/);
    await expect(page.locator("select[name='dataset[embargo]']")).toHaveValue("none");
    await expect(page.locator("input[name='dataset[release_date]']")).toHaveValue("");
  });
});
