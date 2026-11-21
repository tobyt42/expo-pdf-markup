---
'@tobyt/expo-pdf-markup': minor
---

On Android, ink points are now cleaned up when an annotation set is written, exactly as on web: each ink coordinate is rounded to the nearest 0.1 pt (written with at most one decimal digit, and whole numbers without `.0`) and consecutive duplicate ink points within an ink stroke are dropped. A stroke that collapses to a single point is kept as two identical points so it still draws as a dot. Rounding is done after widening Android's `Float` coordinates to `Double`, so long values such as `307.70001220703125` are no longer written. Ink points keep full precision while drawing and moving; highlight, underline, text and stamp bounds and all other fields are written exactly as before, and ink points are still written in object form. The ink coordinate values written will differ slightly from earlier releases.
