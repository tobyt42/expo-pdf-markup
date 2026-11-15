# Annotation validation for spec #126

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

The iPhone result bundle is `build/test-results/ios-1794753626.xcresult`; the iPad result bundle is `build/test-results/ios-1794753664.xcresult` in the #127 worktree. Live PDFView stamp screenshots are retained as XCTest attachments. Result bundles are build artifacts, not checked-in fixtures.

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
