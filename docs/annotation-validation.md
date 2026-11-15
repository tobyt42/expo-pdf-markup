# Annotation validation for spec #126

## Manual regression PDFs in the example app

The example's horizontal document picker includes **Scan regression (6 pages)** and
**Text regression (4 pages)**. Scroll the document row to find them. Both files are
bundled in `example/assets/`; no external document or download is required.

| Sample | Pages | Purpose |
| --- | --- | --- |
| Scan regression | 1–4 | Image-only MediaBox `[0,0,800,1000]`, CropBox `[100,80,700,920]`, rotations 0/90/180/270 |
| Scan regression | 5 | Image-only uncropped, zero-origin control |
| Scan regression | 6 | Image-only zero-origin CropBox `[0,0,600,840]` with different right/top edges |
| Text regression | 1–4 | The same nonzero crop and rotations, with an actual selectable-text sentence |

The scan's labels, lines and asymmetric blue/green anchors are raster pixels; the PDF
contains no selectable text. On the text controls, the sentence beginning “Selectable
text” is real PDF text, while the surrounding visual guides remain rasterized.

1. Select **Scan regression**, then **Ink**. Trace an anchor or staff line; the stroke
   must stay in place when you lift your finger.
2. Select **Highlight** or **Underline** and drag a rectangle over a guide. The page
   must stay still; highlighting fills the area and underlining follows its lower edge.
3. Try **Text**, then **Stamp** with **Note**, **Star** and **Emoji**, including near the
   visible edges. Check placement and clipping on all four rotated pages.
4. Select **Move** or **Eraser**. Blue outlines and touch targets must agree with the
   marks. Switch to **View** to navigate/pinch, then repeat after zooming and scrolling.
5. Repeat with **Text regression**, and compare the scan's zero-origin controls. Book
   mode makes it easy to review each rotation separately.
6. Open **Annotations → Show raw JSON** to inspect the saved paths and bounds. The
   example keeps annotations in memory and clears them when changing documents or
   restarting; this UI does not itself test persistent save/reopen or thumbnails.

Regenerate both checked-in PDFs with `python3 scripts/generate_annotation_pdfs.py`
(requires Pillow >= 10.1 and PyMuPDF; installation is documented in the script).
All fixture content is generated for this project and is redistributable.

## Coordinate slice (#127), 2026-11-15

All repository changes and native builds ran in a task-specific linked worktree.

| Check | Result |
| --- | --- |
| `npm run qa:ts` | Passed; 25 suites, 282 tests passed, 72 tests skipped by the existing platform configuration |
| `npm run qa:ios` | Passed; formatting, SwiftLint (no serious violations), 95 XCTest cases |
| iPhone 13 mini, iOS 26.4 simulator (locally named `cramped`) | 95 XCTest cases passed |
| iPad Pro 13-inch (M5), iOS 26.4 simulator | 95 XCTest cases passed |
| `npm run format:swift:check` and `git diff --check` | Passed |
| Android shared-fixture QA | Run independently with the shared-fixture implementation; see PR validation for the result |

The iPhone result bundle is `build/test-results/ios-1794753626.xcresult`; the iPad result bundle is `build/test-results/ios-1794753664.xcresult` in the integration worktree. Live PDFView stamp screenshots are retained as XCTest attachments. Result bundles are build artifacts, not checked-in fixtures.

### Failure evidence before correction

- Live ink committed on CropBox `[100,80,700,920]` serialized native points `(180,200)` and `(280,200)` instead of visible points `(80,120)` and `(180,120)`. The regression passed after routing live creation through the coordinate adapter and shared serializer.
- Native thumbnail rendering placed zero pixels of each music-note, star and emoji stamp within the expected visible rectangle. The same pixel regression passed after correcting the custom annotation drawing-context origin.
- Highlight, underline, text and stamp import used `(80,120)` as native bounds instead of `(180,200)` on that cropped page. The load-boundary regression passed after applying the shared coordinate adapter.
- Rotated free-text loading expanded the rectangle along the wrong axis, changing visible bounds `(80,120,240,40)` to `(80,29,240,131)`. Normalizing text dimensions before transforming into native space made repeated round trips stable.

The final suite covers crop controls, rotations, live ink, rendered pixels, shared v1 fixture preservation, zoom/scroll movement, outline geometry, hit targets and live glyph rendering before/after annotation reload. Synthetic raster PDF fixtures are generated in the tests; their text-bearing variant adds project-owned text.

### Remaining manual validation

Automated input tests drive overlay callbacks and native gesture handlers. They do not synthesize physical finger or Apple Pencil events. Real-device checks with finger/Pencil on iPhone and iPad remain outstanding. This is distinct from the completed simulator view/rendering checks. Package publication remains a maintainer action.

### Reproduction

Prepare the example project's XCTest target with `ruby scripts/add_test_target.rb`, run CocoaPods installation, then use:

```sh
npm run qa:ios
IOS_TEST_DESTINATION='platform=iOS Simulator,name=iPad Pro 13-inch (M5)' npm run test:swift
npm run qa:ts
```

Use an installed simulator name or ID when the devices above are unavailable. `scripts/test-swift.sh` writes a fresh `.xcresult` bundle for each invocation.

## Area-markup slice (#128), 2026-11-15

| Check | Result |
| --- | --- |
| `npm run qa:ts` | Passed; 25 suites, 282 tests passed, 72 existing platform skips |
| `npm run qa:ios` | Passed; formatting, SwiftLint, 101 XCTest cases on iPhone 13 mini / iOS 26.4 |
| iPad Pro 13-inch (M5), iOS 26.4 | 101 XCTest cases passed, with area tests using the tablet screen dimensions |
| Android | The unchanged shared-fixture implementation passed its 97 JVM tests and ktlint; no Android source changes were required in this slice |

The final iPhone result bundle is `build/test-results/ios-1794769031.xcresult`; the iPad result bundle is `build/test-results/ios-1794769069.xcresult`. The integration worktree retains these bundles alongside the coordinate-slice artifacts.

### Failure evidence and corrected behavior

- Before the area overlay, the image-only highlight regression left scrolling enabled and had no input overlay capable of producing markup. The same drag now produces a visible rectangle and serialized visible bounds `(80,120,100,40)` without moving the scroll offset.
- Native PDFKit underline rendering selected the wrong edge at 90/180/270 degrees. Ordered quadrilaterals corrected the edge but still left the 180-degree baseline outside the selected rectangle. At a crop-edge rectangle `(80,1,100,40)`, no underline pixels remained visible. A small native underline renderer now draws the visible lower edge directly; rendering, reopened marks and their hit targets agree at every rotation, including that crop edge.
- The final area suite exercises both tools on raster-only and selectable-text PDFs across nonzero-origin, zero-origin and right/top crop controls. It checks serialized geometry, zoom/scroll input, movement, rendered output and fresh-view reopen. Cancellation, all tool switches, prior scrolling/gesture-state restoration, source changes, the `page` prop and book-mode hardware keys discard stale drags and leave navigation usable.

These are simulator PDFKit/view tests driven through the existing overlay callbacks and native gesture handlers. Physical finger/Pencil input on real iPhone/iPad devices remains a separate outstanding manual check. No package was published.

## Final review corrections, 2026-11-15

| Check | Result |
| --- | --- |
| `npm run qa:ts` | Passed; 25 suites, 282 tests passed, 72 existing platform skips |
| `npm run qa:ios` | Passed; formatting, SwiftLint with no serious violations, and all 105 XCTest cases on iPhone 13 mini / iOS 26.4 |
| iPad Pro 13-inch (M5), iOS 26.4 | All 105 XCTest cases passed |
| `npm run format:swift:check` and `git diff --check` | Passed |
| Android | Source unchanged by the final review fixes; the earlier 97 passing JVM tests and ktlint result still apply |

The final retained iPhone bundle is `build/test-results/ios-1794771326.xcresult`; the final iPad bundle is `build/test-results/ios-1794771374.xcresult` in the integration worktree. Live rotated-text and stamp snapshots are retained as XCTest attachments.

The review corrections close the remaining live-input and custom-rendering boundaries:

- Live text creation and editing now measure integral dimensions in shared visible-page space and reuse the serializer for native construction. The first live regression reproduced bounds changing from approximately `141.28 × 26.4` to `142 × 27` on reload even at rotation 0; the native/shared axis mismatch also affected rotated pages. Final tests drive text taps, creation, editing to a longer string and fresh-document reload at all four rotations, asserting stable bounds, IDs, timestamps, color, font, content and actual horizontal text pixels in thumbnails and the live view.
- Before the drawing correction, all three music/star/emoji stamps painted zero changed thumbnail pixels in their intended rectangles at rotations 90/180/270, before and after annotation reload. Live appearance recording and whole-page rendering use different PDFKit clips. The shared adapter now draws the same visible content in both contexts; transparent native appearance padding remains separate from model bounds, outlines and hit targets. Full-size and scaled thumbnails, live snapshots, and a full-page rotated `L` orientation control pass.
- A live underline regression found the wrong edge at rotations 90/180/270 even though the existing thumbnail checks passed. PDFKit bypassed the custom draw override for its built-in live underline presentation. Underlines now use a custom native appearance while retaining the public `underline` model type. Final tests check the visible lower edge in live views and thumbnails, then reload and move the mark while preserving its metadata and matching hit geometry.

Early hosted-suite attempts stalled in UIKit window presentation after PDFKit/Vision analysis occupied the dispatch worker pool. Stack sampling identified `UIWindow.makeKeyAndVisible` waiting for corner-bitmap work, rather than a rendering assertion failure. The new rendering harness now attaches temporary views to the existing app window, explicitly clears documents/removes its views between rotations, and preserves the app's window/root state. The final complete suite passes on both simulator configurations; no private PDFKit flags or swizzling are used.

Physical finger/Pencil validation remains outstanding, separately from these completed simulator rendering and callback-driven interaction checks. No package was published.
