---
'@tobyt/expo-pdf-markup': minor
---

On iOS, ink points are now cleaned up when an annotation set is written, exactly as on web and Android: each ink coordinate is rounded to the nearest 0.1 pt (written with at most one decimal digit, and whole numbers without `.0`) and consecutive duplicate ink points within an ink stroke are dropped. A stroke that collapses to a single point is kept as two identical points so it still draws as a dot. This also applies to ink points that iOS reads back out of PDFKit after a stroke is drawn or moved, so long values such as `307.6921296296296` are no longer written. Ink points keep full precision while drawing and moving; highlight, underline, text and stamp bounds and all other fields are written exactly as before, and ink points are still written in object form. The ink coordinate values written will differ slightly from earlier releases.
