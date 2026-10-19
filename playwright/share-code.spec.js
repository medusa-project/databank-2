const { test, expect } = require("@playwright/test");
const AxeBuilder = require("@axe-core/playwright").default;

test("private sharing controls support keyboard use, copying, guest access and revocation", async ({ page, browser, baseURL }) => {
  const email = `sharing-${Date.now()}@example.test`;
  const auth = await page.request.post("/auth/developer/callback", {
    form: { email, name: "Sharing Tester", role: "depositor" },
  });
  expect(auth.ok()).toBeTruthy();

  const created = await page.request.post("/datasets", {
    form: {
      "dataset[title]": "Private sharing browser test",
      "dataset[description]": "Private dataset for sharing accessibility checks",
    },
  });
  expect(created.ok()).toBeTruthy();
  const showPath = new URL(created.url()).pathname.replace(/\/edit$/, "");
  const guest = await browser.newContext({ baseURL });

  try {
    await page.goto(showPath);
    const generate = page.getByRole("button", { name: "Generate private sharing link", exact: true });
    await generate.focus();
    await expect(generate).toBeFocused();
    await page.keyboard.press("Enter");

    const sharing = page.getByRole("region", { name: "Private Sharing Link", exact: true });
    const link = sharing.getByLabel("Private sharing URL", { exact: true });
    await expect(link).toBeVisible();
    await expect(link).toHaveJSProperty("readOnly", true);
    const shareURL = new URL(await link.inputValue());
    const sharedPath = shareURL.pathname + shareURL.search;

    const axe = await new AxeBuilder({ page })
      .include("#private-sharing-heading")
      .include("section[aria-labelledby='private-sharing-heading']")
      .withTags(["wcag2a", "wcag2aa", "wcag21aa", "wcag22aa"])
      .analyze();
    expect(axe.violations).toEqual([]);

    await page.evaluate(() => {
      Object.defineProperty(navigator, "clipboard", {
        configurable: true,
        value: { writeText: async (value) => { window.copiedShareURL = value; } },
      });
    });
    const copy = sharing.getByRole("button", { name: "Copy sharing link", exact: true });
    await copy.focus();
    await page.keyboard.press("Enter");
    await expect(sharing.getByRole("status")).toHaveText("Sharing link copied to clipboard.");
    expect(await page.evaluate(() => window.copiedShareURL)).toBe(await link.inputValue());

    const guestPage = await guest.newPage();
    await guestPage.goto(sharedPath);
    await expect(guestPage.getByRole("heading", { name: "Private sharing browser test", exact: true })).toBeVisible();
    await expect(guestPage.getByRole("region", { name: "Private Sharing Link", exact: true })).toHaveCount(0);

    const remove = sharing.getByRole("button", { name: "Delete sharing link", exact: true });
    await remove.focus();
    await page.keyboard.press("Enter");
    await expect(page.getByRole("button", { name: "Generate private sharing link", exact: true })).toBeVisible();

    await guestPage.goto(sharedPath);
    await expect(guestPage).toHaveURL(/\/login$/);
  } finally {
    await guest.close();
    await page.request.delete(showPath);
  }
});
