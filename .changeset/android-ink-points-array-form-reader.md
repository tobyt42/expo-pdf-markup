---
'@tobyt/expo-pdf-markup': minor
---

Android now reads ink points in array form (`[x, y]`) as well as object form (`{"x": …, "y": …}`), including a mix of both within one ink stroke. A malformed ink point (missing values, wrong types or the wrong number of values) is now skipped rather than making the whole annotation set fail to load, matching iOS. Android still writes ink points in object form.
