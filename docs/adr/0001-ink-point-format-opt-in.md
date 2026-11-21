# Array-form ink points are opt-in, and the annotation set stays at version 1

Large ink-heavy annotation sets outgrew a host app's storage (#82), and writing ink points in array form (`[x, y]`) instead of object form (`{"x": …, "y": …}`) cuts their size substantially. But readers released before this change fail on array form: iOS rejects the whole annotation set, Android throws, and web draws `NaN`. Only the host app knows when its oldest version still in use can read array form, so readers accept both forms in every release, and writers emit array form only when the host app sets `inkPointFormat="array"`. The default stays object form until a later major release. Rounding ink points to 0.1 pt and dropping consecutive duplicates always happen, because both keep object form readable by every existing reader.

## Considered Options

- **Two releases (readers first, writers in a later major).** Rejected: the library still cannot know when the host app's older versions are gone, and it forces a major release purely for timing.
- **Always write array form.** Rejected: any older app opening an annotation set written by a newer one loses every annotation on it.
- **Bump `version` to 2 for array form.** Rejected: no existing reader checks `version` (web even resets it to 1), so the bump would protect nobody, and each ink point already identifies its own form.

## Consequences

- An annotation set may contain both forms, even within one ink stroke, and readers handle each ink point on its own.
- The public `AnnotationPoint` type keeps object form. Host apps that inspect raw JSON written in array form must read it through the exported `parseAnnotations` helper.
- Existing annotation sets only shrink when they are next edited, since nothing is written on load.
