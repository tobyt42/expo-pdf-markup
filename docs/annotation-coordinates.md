# Annotation coordinates

All platforms exchange `AnnotationsData` version 1 using the same visible-page coordinate system:

- Units are PDF points, independent of screen density, zoom and scrolling.
- The origin `(0, 0)` is the bottom-left of the visible page after its PDF rotation.
- `x` increases rightward; `y` increases upward.
- Ink `paths` contain visible-page points. Rectangular `bounds` use the same space: `x` and `y` locate the bottom-left, with positive `width` and `height`.
- The contract applies to ink, highlight, underline, text/freeText, stamps, and text-input-request points. `page` remains a zero-based page index.

For example, a PDF with MediaBox `[0,0,800,1000]` and CropBox `[100,80,700,920]` has a visible size of 600 by 840 points at rotation 0. A model point `(80,120)` covers native PDF page point `(180,200)`. With clockwise rotation 90, visible size is 840 by 600 and the same model point covers native page point `(580,160)`.

## iOS boundaries

PDFKit touch conversion and native annotation rectangles use unrotated PDF page coordinates, including the crop origin. `AnnotationCoordinates` converts these coordinates to/from the interchange model. Loading and serialization apply this adapter in opposite directions, including page rotation.

PDFKit ink paths are local to their annotation rectangle. The module converts native page points to local path points when constructing an annotation, and adds the rectangle origin before serializing, outlining or hit-testing it. Live ink uses the same construction path as loaded ink. Custom stamp drawing additionally accounts for the display box origin in PDFKit's drawing context. Area underlines draw the displayed rectangle's lower edge directly in the visible-page drawing context, so page rotation cannot move the line to another edge or outside the crop.

Moving annotations operates in visible-page coordinates and clamps to the visible page dimensions. Outlines and eraser/move hit targets use the rendered native geometry. Neither zooming nor scrolling alters saved coordinates.

## Existing v1 data

Valid web/Android v1 coordinates keep their existing placement; no schema change or automatic migration is applied. IDs, page indices, content, color and styling survive load/save cycles. `text` and `freeText` both render as native free text while retaining their interchange type.

Historical native v1 records do not reliably identify their originating platform or coordinate convention. A record containing native page coordinates can be indistinguishable from an intentional visible-page placement. The module does not guess the original intent, subtract an offset from every stored record, or rewrite a host application's store. Back up existing records and review affected documents when upgrading. Recovery of ambiguous historical data requires application-specific information about how that data was created.

Consumers must rebuild their native iOS application to adopt the Swift correction. Updating JavaScript or delivering an OTA update alone does not replace compiled native code. Package publication is a separate maintainer action.

## Regression coverage

`ios/Tests/AnnotationCoordinateTests.swift` generates project-owned raster-only PDF fixtures with asymmetric anchors, with optional selectable text. Coverage includes nonzero x/y crop origins, zero-origin media-box and right/top-only crop controls, rotations 0/90/180/270, live ink commitment, rendered thumbnails, zoom/scroll movement, editing outlines, hit targets and live stamp snapshots before/after reloading.

`fixtures/annotations-v1.json` supplies the same marks to iOS, web and Android model tests, including ink, highlight/underline, text/freeText and music/star/emoji stamps. Repeated round trips assert placement and metadata preservation.

Native interaction tests drive the existing overlay callbacks and gesture-handler seam. They exercise the real PDFKit view and rendering, but do not synthesize physical finger/Pencil events. Simulator results and outstanding physical-device checks are recorded separately in the implementation's validation report.

## Area markup on iOS

The highlight and underline tools capture a one-finger rectangular drag on both scanned and text-bearing PDFs. No text selection or OCR is required, and rectangles do not snap to text lines. A highlight fills the chosen area; an underline marks its displayed lower edge. The same visible-page bounds are emitted through `onAnnotationsChanged` and retained after reloading.

Touch scrolling, pinch zoom and book-mode touch turns are suspended while the tool is active. Select `annotationMode="none"` for touch navigation and zoom, then reselect the desired markup tool. The `page` prop and book-mode hardware keys remain available during markup. Page/source/display changes, cancelled gestures and tool switches discard an unfinished drag; a drag cannot transfer its mark to another page. Leaving the tool restores the previous scrolling and gesture state.

`ios/Tests/AreaMarkupTests.swift` covers the input-to-render-to-serialization path with raster-only and selectable-text controls, crop controls, all rotations, zoom/scroll, fresh-view reopen, movement/hit geometry, cancellation, tool switching and explicit navigation. Tests use each simulator's screen dimensions. As with the coordinate suite, callback-driven tests do not replace physical finger/Pencil validation.
