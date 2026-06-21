---
"@tobyt/expo-pdf-markup": minor
---

Add `stamp` annotations for placing consumer-defined text glyphs (e.g. emoji) onto a PDF. New `StampAnnotation` type, `'stamp'` annotation mode, and `stampText`/`stampSize` props let apps arm a stamp (from their own picker UI) and tap to place it; stamps support move and eraser like other bounds-based annotations. A new `StampDefinition` type is exported as a convenience shape for organizing a custom stamp set. Image-backed stamps were intentionally left out — a stored local file path can go stale (app reinstall, cache eviction) and silently break previously-placed stamps, so this stays text-only for now.
