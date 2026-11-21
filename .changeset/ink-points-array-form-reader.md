---
'@tobyt/expo-pdf-markup': minor
---

Web now reads ink points in array form (`[x, y]`) as well as object form (`{"x": …, "y": …}`), including a mix of both within one ink stroke. A malformed ink point is skipped rather than drawn as `NaN`, and the rest of the annotation set still loads. Adds a public, platform-neutral `parseAnnotations(json)` helper, which reads either form and always returns ink points in object form, throwing on JSON that can't be parsed or has no `annotations` array, and an `AnnotationPointArray` type. `AnnotationPoint` and `InkAnnotation` are unchanged, and nothing about how annotation sets are written changes in this release.
