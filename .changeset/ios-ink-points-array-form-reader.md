---
'@tobyt/expo-pdf-markup': minor
---

iOS now reads ink points in array form (`[x, y]`) as well as object form (`{"x": …, "y": …}`), including a mix of both within one ink stroke. Previously a single array-form ink point made iOS reject the whole annotation set; now each ink point is read on its own, a malformed one is skipped, and the rest of the ink stroke and the annotation set load as normal. Ink loaded in either form can be moved, erased and saved again, and iOS still writes ink points in object form.
