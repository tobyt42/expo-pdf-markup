---
"@tobyt/expo-pdf-markup": patch
---

Always serialise `paths` on ink annotations, even when the platform returns no stroke geometry. The `Annotation` type declares `paths` as non-optional, but iOS and Android both omitted the key when geometry was missing, so consumers dereferencing `annotation.paths` crashed with a `TypeError` instead of seeing an empty stroke list.
