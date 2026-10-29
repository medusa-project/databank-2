const { test, expect } = require("@playwright/test");

for (const width of [1920, 1366, 1024, 768, 390]) {
  test(`dataset search fills its layout without overflowing the form at ${width}px`, async ({
    page,
  }) => {
    await page.setViewportSize({ width, height: 900 });
    await page.goto("/datasets");
    await expect(page.locator(".dataset-result-card").first()).toBeVisible();
    await page.evaluate(() => document.fonts.ready);

    const layout = await page.evaluate(() => {
      const bounds = (selector) =>
        document.querySelector(selector).getBoundingClientRect().toJSON();
      const form = document.querySelector(".datasets-search-form");
      return {
        formWidth: form.clientWidth,
        scrollWidth: form.scrollWidth,
        grid: bounds(".datasets-search-layout"),
        filters: bounds(".datasets-filters-panel"),
        results: bounds(".datasets-results-panel"),
        card: bounds(".dataset-result-card"),
        go: bounds(".datasets-go-button"),
      };
    });

    expect(layout.scrollWidth).toBeLessThanOrEqual(layout.formWidth);
    expect(layout.go.right).toBeLessThanOrEqual(layout.grid.right + 1);
    expect(Math.abs(layout.card.right - layout.grid.right)).toBeLessThan(1);
    expect(Math.abs(layout.card.width - layout.results.width)).toBeLessThan(1);

    if (width > 960) {
      expect(layout.filters.right).toBeLessThan(layout.results.left);
      expect(layout.filters.top).toBe(layout.results.top);
    } else {
      expect(layout.filters.bottom).toBeLessThan(layout.results.top);
    }

  });
}

test("curator metadata and status badges share a row when space permits", async ({
  page,
}) => {
  const response = await page.request.post("/auth/developer/callback", {
    form: {
      email: "search-layout-curator@example.test",
      name: "Search Layout Curator",
      role: "curator",
    },
  });
  expect(response.ok()).toBeTruthy();
  await page.setViewportSize({ width: 1920, height: 900 });
  await page.goto("/datasets");
  const badges = page.locator(".dataset-result-badges").first();
  await expect(badges).toContainText("updated:");
  await page.evaluate(() => document.fonts.ready);

  const layout = await badges.locator(":scope > .idb-badge").evaluateAll(
    (elements) => elements.map((element) => element.getBoundingClientRect().toJSON()),
  );
  expect(layout.length).toBeGreaterThan(6);
  expect(
    Math.max(...layout.map((badge) => badge.top)) -
      Math.min(...layout.map((badge) => badge.top)),
  ).toBeLessThan(3);

  await page.setViewportSize({ width: 390, height: 900 });
  const wrapped = await badges.evaluate((element) => ({
    width: element.clientWidth,
    scrollWidth: element.scrollWidth,
    rows: new Set(
      Array.from(element.children, (badge) =>
        Math.round(badge.getBoundingClientRect().top)),
    ).size,
  }));
  expect(wrapped.scrollWidth).toBeLessThanOrEqual(wrapped.width);
  expect(wrapped.rows).toBeGreaterThan(1);
});
