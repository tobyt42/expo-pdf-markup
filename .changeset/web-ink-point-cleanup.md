---
'@tobyt/expo-pdf-markup': minor
---

On web, ink points are now cleaned up when an annotation set is written: each ink coordinate is rounded to the nearest 0.1 pt (written with at most one decimal digit, and whole numbers without `.0`) and consecutive duplicate ink points within an ink stroke are dropped. A stroke that collapses to a single point is kept as two identical points so it still draws as a dot. Ink points keep full precision while drawing and moving; highlight, underline, text and stamp bounds and all other fields are written exactly as before. This makes ink-heavy annotation sets considerably smaller, but the ink coordinate values written will differ slightly from earlier releases.
