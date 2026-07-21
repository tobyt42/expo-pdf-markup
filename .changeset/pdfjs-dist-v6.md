---
"@tobyt/expo-pdf-markup": patch
---

Support pdfjs-dist v6 on the web renderer. Adapt to the v6 API changes: `getDocument` now takes a parameters object (`{ url }`) rather than a bare string, and `PDFDocumentProxy.destroy()` was removed in favour of `loadingTask.destroy()`. The explicit `canvas` passed to `page.render()` satisfies the stricter v6 types. These calls remain compatible with earlier pdfjs-dist versions, so the optional peer dependency range is unchanged.
