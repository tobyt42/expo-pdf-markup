# @tobyt/expo-pdf-markup

## 1.1.2

### Patch Changes

- 2970fc6: Support pdfjs-dist v6 on the web renderer. Adapt to the v6 API changes: `getDocument` now takes a parameters object (`{ url }`) rather than a bare string, and `PDFDocumentProxy.destroy()` was removed in favour of `loadingTask.destroy()`. Pass `canvas: null` to `page.render()` so pdfjs keeps rendering into our own 2D context (the v6 types made `canvas` required) without taking ownership of the canvas element.

  pdfjs-dist v6 also moved image decoding (JBIG2/CCITT fax, JPEG2000, ICC colour) into WebAssembly, which is fetched at runtime from a configurable `wasmUrl`. Without it, affected image data — scanned pages and some music notation — renders blank. `withPdfMarkup` now copies the WASM files to `public/wasm/`, the view sets `wasmUrl` to `./wasm/` by default, and a new `setPdfJsWasmUrl()` export lets consumers point it elsewhere.

  These calls remain compatible with earlier pdfjs-dist versions, so the optional peer dependency range is unchanged.

- a361c91: Verify compatibility with Expo SDK 57 (React Native 0.86). Fix TypeScript strictness errors surfaced by the updated toolchain (`verbatimModuleSyntax`, `noUncheckedIndexedAccess`) with no behaviour change.

## 1.1.1

### Patch Changes

- 3f4fa8c: Android: fix touch-interception lifecycle in the PDF view. The view previously called `requestDisallowInterceptTouchEvent(true)` on every touch event and never released it, and in-progress gestures were never reset when interrupted. This could leave stale touch state on ancestor views shared with sibling screens (e.g. list rows behind the PDF screen becoming unresponsive to taps after navigating back, especially after locking/unlocking the device), and caused unnecessary gesture-handler contention while scrolling.

  Now the parent intercept hold is requested on `ACTION_DOWN` and released on the final `ACTION_UP`/`ACTION_CANCEL` (held across multi-touch pinch), and all in-progress gestures (ink stroke, highlight/underline drag, annotation move, fling) are cancelled and the hold released when the window loses focus (device lock) or the view detaches. Note: an ink stroke interrupted by a device lock is discarded rather than committed.

## 1.1.0

### Minor Changes

- 24c58b8: Add `stamp` annotations for placing consumer-defined text glyphs (e.g. emoji) onto a PDF. New `StampAnnotation` type, `'stamp'` annotation mode, and `stampText`/`stampSize` props let apps arm a stamp (from their own picker UI) and tap to place it; stamps support move and eraser like other bounds-based annotations. A new `StampDefinition` type is exported as a convenience shape for organizing a custom stamp set. Image-backed stamps were intentionally left out — a stored local file path can go stale (app reinstall, cache eviction) and silently break previously-placed stamps, so this stays text-only for now.

### Patch Changes

- 850b4f9: Routine dependency maintenance: upgrade to the latest Expo SDK 55 patch release. Bumps `expo` (55.0.5 → 55.0.26) and `react-native` (0.83.2 → 0.83.6) in the module, and `expo`, `expo-asset`, `expo-font`, `react-native`, `react`, `react-dom` to their SDK 55.0.26-compatible versions in the example app. No runtime behavior changes.
- 95b8c0d: Routine dependency maintenance: patch/minor bumps for transitive and dev dependencies (`@babel/plugin-transform-modules-systemjs`, `@xmldom/xmldom`, `lodash`, `node-forge`, `flatted`, `picomatch`, `yaml`, `brace-expansion`, `shell-quote`, `markdown-it`, `linkify-it`, `form-data`, `hasown`, `ws`), example app `react`/`react-dom`/`@types/react`, and CI Actions (`checkout`, `setup-node`, `upload-pages-artifact`, `deploy-pages`). No runtime behavior changes.

## 1.0.1

### Patch Changes

- 16e0e87: Fix iOS ink strokes missing their first contact point

  Replaces `UIPanGestureRecognizer` with direct `touchesBegan/Moved/Ended` handling for ink drawing. The pan gesture had a minimum-distance threshold that silently dropped the start of every stroke — most noticeable with third-party styluses (e.g. Metapen) where initial contact is slow and deliberate.

  Also disables PDFKit's built-in gesture recognizers while in ink mode, preventing text selection from firing during what was previously the gesture recognition dead zone.

## 1.0.0

### Major Changes

- ea50181: Stable 1.0.0 release — production-ready API for displaying and annotating PDFs on iOS, Android, and Web.

### Patch Changes

- 906ce89: Fix Android blank PDF and scroll position loss when navigating back to a screen containing the PDF view

## 0.6.1

### Patch Changes

- e1a942b: Fix Android custom font rendering

## 0.6.0

### Minor Changes

- fc961ab: Add support for a custom font for text markups
- 26bdae1: When in Move or Eraser mode, annotations are now surrounded by an outline to indicate the scope of the move/erasure
- 26bdae1: A Move tool was added for drag and drop repositioning of annotations
- 76f9b23: Text annotations can now be edited (breaking change, see example/docs)

### Patch Changes

- dae52fb: Reset currentSource in close
- 8146a57: Add padding to Android freeText annotation bounds to prevent text from being clipped when rendered

## 0.5.0

### Minor Changes

- 049130a: Example app is now deployed to Github Pages
- 049130a: Default pdfjs worker source for web implementation is now relative
- e62d562: Support optionally rendering text input prompt on JavaScript side

## 0.4.0

### Minor Changes

- 519e27b: Update metro config plugin so it works in a monorepo too
- 4898177: The onPageChanged event now returns page width and height.
- 5423941: When using gestures to zoom on Web, only the PDF is zoomed in/out instead of the entire UI.

### Patch Changes

- f15901a: Move spacer in Web implementation so it only appears inbetween pages

## 0.3.1

### Patch Changes

- Fixed an issue on iOS, where after selecting a different colour, the previous colour would still be used for the live stroke.

## 0.3.0

### Minor Changes

- PDF rendering and markup is now also supported on Web.

### Patch Changes

- 4dafaf4: Fixed documentation for the source prop - it only accepts absolute local file paths; remote URLs are not supported. Updated the README usage example to reflect real-world usage (loading a bundled asset via expo-asset) and demonstrate key props like annotationMode, annotationColor, annotationLineWidth, annotations, and the event callbacks.

## 0.2.3

### Patch Changes

- fix: exclude ios/Tests from podspec source_files to prevent XCTest

## 0.2.2

### Patch Changes

- Fix gap at top of first page on iOS by changing pageBreakMargins to apply all margin to the bottom

## 0.2.1

### Patch Changes

- Fix freeText annotation colour round-trip by storing the original hex string as a custom PDF annotation key, preventing loss when PDFKit's fontColor returns nil outside a document context

## 0.2.0

### Minor Changes

- 78be89c: Fix freeText annotation colour lost after serialisation on iOS.

  PDFKit stores freeText annotation colours in `fontColor` (not `annotation.color`, which is always `.clear` for text annotations). The `toModel` serialiser was unconditionally reading `annotation.color`, causing all freeText colours to round-trip as black. The fix reads `fontColor` for `text`/`freeText` annotation types and falls back to `annotation.color` for all others.

## 0.1.0

### Minor Changes

- Initial release.
