# PDF browser validation

After installing root and example dependencies, run `npm run build` at the
repository root and export the example from `example/`:

```sh
npx --no-install expo export --platform web --output-dir ../site/example
```

Then, from this directory:

```sh
npm ci
npx --no-install playwright install chromium
npm test
```

The server uses the deployment base from `example/app.json`. Tests open the
actual export and require both pages of `example/assets/test.pdf` to complete
PDF.js rendering with visible ink and paper on the PDF canvas. They observe
worker startup and browser/network errors separately from the annotation layer.
A second case breaks the worker and requires the same rendering verdict to fail.
Export refreshes version-coupled worker and WASM assets through `metro.js`.

This fixture checks browser PDF rendering and worker integration. It does not
establish that any particular WASM image decoder executed. CI downloads the
export produced by the web build job instead of rebuilding another copy.
