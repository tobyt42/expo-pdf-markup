---
"@tobyt/expo-pdf-markup": patch
---

Support pdfjs-dist v6 on the web renderer. Adapt to the v6 API changes: `getDocument` now takes a parameters object (`{ url }`) rather than a bare string, and `PDFDocumentProxy.destroy()` was removed in favour of `loadingTask.destroy()`. Pass `canvas: null` to `page.render()` so pdfjs keeps rendering into our own 2D context (the v6 types made `canvas` required) without taking ownership of the canvas element.

pdfjs-dist v6 also moved image decoding (JBIG2/CCITT fax, JPEG2000, ICC colour) into WebAssembly, which is fetched at runtime from a configurable `wasmUrl`. Without it, affected image data — scanned pages and some music notation — renders blank. `withPdfMarkup` now copies the WASM files to `public/wasm/`, the view sets `wasmUrl` to `./wasm/` by default, and a new `setPdfJsWasmUrl()` export lets consumers point it elsewhere.

These calls remain compatible with earlier pdfjs-dist versions, so the optional peer dependency range is unchanged.
