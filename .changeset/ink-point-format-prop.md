---
'@tobyt/expo-pdf-markup': minor
---

Adds an `inkPointFormat` view prop on iOS, Android and web, so the host app can choose how ink points are written: `'object'` (`{"x": …, "y": …}`, the default) or `'array'` (`[x, y]`), which makes ink-heavy annotation sets noticeably smaller. Ink points are cleaned up in exactly the same way in both forms, and identically on every platform, and `version` stays at 1. Changing the prop doesn't write anything or fire `onAnnotationsChanged`; it applies from the next edit, and any annotation set loaded in either form is then written in the chosen form. Only choose `'array'` once every version of your app that might read the annotation set includes this release or a later one, because earlier releases can't read array form. Also exports an `InkPointFormat` type.
