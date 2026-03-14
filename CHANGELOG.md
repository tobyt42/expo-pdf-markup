# @tobyt/expo-pdf-markup

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
