# @tobyt/expo-pdf-markup

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
