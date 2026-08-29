---
'@tobyt/expo-pdf-markup': patch
---

Fix `withPdfMarkup` leaving a stale pdfjs worker in `public/` after a pdfjs-dist upgrade. The Metro plugin copied `pdf.worker.min.mjs` and the `wasm/` assets only when they were absent, so once a project had them the copies were pinned to whichever pdfjs-dist version was installed first. Upgrading pdfjs-dist then broke web rendering with `The API version "x" does not match the Worker version "y"`, and silently stale wasm assets could mis-decode JBIG2/CCITT fax, JPEG2000 and ICC colour data. The plugin now compares each file against the installed pdfjs-dist and re-copies whenever it differs, so upgrades and downgrades both self-correct while unchanged files stay a no-op on Metro restart.
