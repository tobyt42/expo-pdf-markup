# @tobyt/expo-pdf-markup

## 0.2.0

### Minor Changes

- Fix freeText annotation colour lost after serialisation on iOS.

  PDFKit stores freeText annotation colours in `fontColor` (not `annotation.color`, which is always `.clear` for text annotations). The `toModel` serialiser was unconditionally reading `annotation.color`, causing all freeText colours to round-trip as black. The fix reads `fontColor` for `text`/`freeText` annotation types and falls back to `annotation.color` for all others.
