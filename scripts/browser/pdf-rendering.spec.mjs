import { test, expect } from '@playwright/test';

// Observe the PDF layer rather than the transparent annotation canvas. The
// completion marker follows PDF.js's render promise, not onLoadComplete.
async function requirePdfRendering(page, timeout = 30000) {
  await expect(
    page.locator('[data-pdf-layer="pdf"][data-pdf-render-state="complete"]')
  ).toHaveCount(2, { timeout });
  const pixels = await page.locator('[data-pdf-layer="pdf"]').evaluateAll((canvases) =>
    canvases.map((canvas) => {
      const { width, height } = canvas;
      const data = canvas.getContext('2d').getImageData(0, 0, width, height).data;
      let dark = 0;
      let light = 0;
      for (let i = 0; i < data.length; i += 4) {
        if (data[i + 3] < 200) continue;
        if (Math.max(data[i], data[i + 1], data[i + 2]) < 200) dark++;
        if (Math.min(data[i], data[i + 1], data[i + 2]) > 240) light++;
      }
      return { width, height, dark, light };
    })
  );
  for (const canvas of pixels) {
    expect(canvas.width).toBeGreaterThan(100);
    expect(canvas.height).toBeGreaterThan(100);
    expect(canvas.dark, 'PDF page must contain visible ink').toBeGreaterThan(200);
    expect(canvas.light, 'PDF page must contain visible paper').toBeGreaterThan(200);
  }
}

function observeFailures(page) {
  const failures = [];
  const workers = [];
  page.on('worker', (worker) => workers.push(worker.url()));
  page.on('pageerror', (error) => failures.push(error.message));
  page.on('console', (message) => {
    if (message.type() === 'error') failures.push(message.text());
  });
  page.on('response', (response) => {
    if (response.status() >= 400) failures.push(`${response.status()} ${response.url()}`);
  });
  page.on('requestfailed', (request) =>
    failures.push(`${request.failure()?.errorText} ${request.url()}`)
  );
  return { failures, workers };
}

test('exported example renders both fixture pages with the real PDF.js worker', async ({
  page,
}) => {
  const { failures, workers } = observeFailures(page);
  await page.goto('./');
  await requirePdfRendering(page);
  expect(
    workers.some((url) => url.endsWith('/pdf.worker.min.mjs')),
    'real PDF.js worker started'
  ).toBe(true);
  expect(failures, 'browser, asset, network, or rendering failures').toEqual([]);
});

test('the same rendering verdict rejects a broken PDF.js worker', async ({ page }) => {
  let intercepted = 0;
  await page.route('**/pdf.worker.min.mjs', async (route) => {
    intercepted++;
    await route.fulfill({
      contentType: 'text/javascript',
      body: 'throw new Error("Broken worker probe");',
    });
  });
  await page.goto('./');
  await expect(requirePdfRendering(page, 5000)).rejects.toThrow();
  expect(intercepted, 'probe must break the actual worker request').toBeGreaterThan(0);
});
