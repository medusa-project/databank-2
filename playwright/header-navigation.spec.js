const { test, expect, devices } = require("@playwright/test");

test.describe("header navigation desktop behavior", () => {
  test("shows full header menu links on /datasets after clicking Find Data", async ({
    page,
  }) => {
    await page.goto("/");
    const header = page.locator("il-header");

    await expect(
      header.getByRole("link", { name: "Find Data", exact: true }),
    ).toBeVisible();
    await expect(
      header.getByRole("link", { name: "Deposit Dataset", exact: true }),
    ).toBeVisible();

    await header.getByRole("link", { name: "Find Data", exact: true }).click();
    await expect(page).toHaveURL(/\/datasets$/);

    await expect(
      header.getByRole("link", { name: "Deposit Dataset", exact: true }),
    ).toBeVisible();
    await expect(
      header.getByRole("link", { name: "Find Data", exact: true }),
    ).toBeVisible();
    await expect(
      header.getByRole("link", { name: "Policies", exact: true }),
    ).toBeVisible();
    await expect(
      header.getByRole("link", { name: "Guides", exact: true }),
    ).toBeVisible();
    await expect(
      header.getByRole("link", { name: "Contact Us", exact: true }),
    ).toBeVisible();
    await expect(header.getByRole("button", { name: "Menu" })).toHaveCount(0);
  });
});

test.describe("header navigation mobile behavior", () => {
  const iphone = devices["iPhone 12"];

  test.use({
    viewport: iphone.viewport,
    userAgent: iphone.userAgent,
    deviceScaleFactor: iphone.deviceScaleFactor,
    isMobile: iphone.isMobile,
    hasTouch: iphone.hasTouch,
  });

  test("shows Menu button and reveals nav links when opened on /datasets", async ({
    page,
  }) => {
    await page.goto("/");
    const header = page.locator("il-header");
    const menuButton = header.getByRole("button", { name: "Menu" });

    if (await menuButton.isVisible()) {
      await menuButton.click();
    }

    await expect(
      header.getByRole("link", { name: "Find Data", exact: true }),
    ).toBeVisible();

    await header.getByRole("link", { name: "Find Data", exact: true }).click();
    await expect(page).toHaveURL(/\/datasets$/);

    if (await menuButton.isVisible()) {
      await menuButton.click();
    }

    await expect(
      header.getByRole("link", { name: "Deposit Dataset", exact: true }),
    ).toBeVisible();
    await expect(
      header.getByRole("link", { name: "Find Data", exact: true }),
    ).toBeVisible();
    await expect(
      header.getByRole("link", { name: "Policies", exact: true }),
    ).toBeVisible();
    await expect(
      header.getByRole("link", { name: "Guides", exact: true }),
    ).toBeVisible();
    await expect(
      header.getByRole("link", { name: "Contact Us", exact: true }),
    ).toBeVisible();
  });
});

test.describe("welcome page banner", () => {
  test("shows the orange banner image and overlay tagline on the root page", async ({
    page,
  }) => {
    await page.goto("/");

    const welcomeImage = page.locator("#welcome-image");
    await expect(welcomeImage).toBeVisible();

    // Verify the background-image style is set to the banner (not 'none')
    const bgImage = await welcomeImage.evaluate(
      (el) => getComputedStyle(el).backgroundImage,
    );
    expect(bgImage).not.toBe("none");
    expect(bgImage).toContain("orange_data_banner");

    // Verify the overlay text box is visible with the tagline
    const overlay = page.locator("#welcome-overlay");
    await expect(overlay).toBeVisible();

    const overlayStyles = await overlay.evaluate((el) => {
      const style = getComputedStyle(el);
      const rect = el.getBoundingClientRect();
      return {
        backgroundColor: style.backgroundColor,
        borderTopWidth: style.borderTopWidth,
        borderTopStyle: style.borderTopStyle,
        width: rect.width,
        height: rect.height,
      };
    });

    expect(overlayStyles.backgroundColor).toBe("rgb(255, 255, 255)");
    expect(overlayStyles.borderTopWidth).not.toBe("0px");
    expect(overlayStyles.borderTopStyle).toBe("solid");
    expect(overlayStyles.width).toBeGreaterThan(200);
    expect(overlayStyles.height).toBeGreaterThan(40);

    await expect(overlay).toContainText("public access repository");
    await expect(overlay).toContainText("Illinois Data Bank");
    await expect(overlay).toContainText(
      "Learn how we meet trustworthy repository standards",
    );
  });
});

test.describe("pre-deposit section disclosure behavior", () => {
  test("starts closed and allows opening multiple sections simultaneously", async ({ page }) => {
    const response = await page.request.post("/auth/developer/callback", {
      form: {
        email: "parity-tester@example.test",
        name: "Parity Tester",
        role: "depositor",
      },
    });
    expect(response.ok()).toBeTruthy();

    await page.goto("/datasets/pre_deposit");
    await expect(page).toHaveURL(/\/datasets\/pre_deposit$/);

    const sections = page.locator("#main-content details.idb-section-disclosure");
    await expect(sections).toHaveCount(7);

    await expect(sections.nth(0)).toHaveJSProperty("open", false);
    await expect(sections.nth(1)).toHaveJSProperty("open", false);

    await sections.nth(0).locator("summary").click();
    await expect(sections.nth(0)).toHaveJSProperty("open", true);

    await sections.nth(1).locator("summary").click();
    await expect(sections.nth(0)).toHaveJSProperty("open", true);
    await expect(sections.nth(1)).toHaveJSProperty("open", true);
  });
});
