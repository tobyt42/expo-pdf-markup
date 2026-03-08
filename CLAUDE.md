# expo-pdf-markup

Expo module for displaying and annotating PDFs on iOS (native PDFKit), with web fallback stub.

## Quality checks

Run all checks across all platforms:
```
npm run qa
```

Platform-specific QA:
- `npm run qa:ts` — typecheck + ESLint + Prettier (auto-fix) + Jest tests
- `npm run qa:ios` — SwiftLint + SwiftFormat (auto-fix) + XCTest (requires simulator)
- `npm run qa:android` — ktlint + ktlint --format (auto-fix) + Gradle JUnit tests

Individual commands:
- `npm run typecheck` — TypeScript type checking
- `npm run lint` / `npm run lint:swift` / `npm run lint:kotlin` — linting per platform
- `npm run format` / `npm run format:swift` / `npm run format:kotlin` — auto-fix formatting
- `npm run format:check` / `npm run format:swift:check` / `npm run format:kotlin:check` — check formatting
- `npm run test` / `npm run test:swift` / `npm run test:kotlin` — tests per platform

Always run `npm run qa` (or at minimum `npm run qa:ts`) before committing.

## Testing

### TypeScript (Jest)
Tests live in `src/__tests__/`. The jest preset (expo-module-scripts) runs 4 projects: iOS, Android, Web, Node.

- Use `.test.native.ts` suffix for tests that only run on iOS/Android
- Use `.test.web.tsx` suffix for tests that only run on Web/Node
- Use plain `.test.ts` for tests that run everywhere
- Mock `expo` in native tests that import the native view (`requireNativeView`)

### Swift (XCTest)
Tests live in `ios/Tests/`. Run with `npm run test:swift`.

- Uses `@testable internal import ExpoPdfMarkup` (explicit access level required by Swift 6)
- Test target is wired via Podfile (`inherit! :search_paths`) and Xcode project
- Test PDF resource is bundled in the test target for `loadPdf` / `goToPage` tests
- To add the test target to a fresh example project, run `ruby scripts/add_test_target.rb` then `pod install`

### Kotlin (JUnit)
Tests live in `android/src/test/`. Run with `npm run test:kotlin`.

- Pure JUnit (no Robolectric) — tests cover navigation logic, bounds checking, source dedup
- Runs via Gradle from the example project: `./gradlew :tobyt-expo-pdf-markup:testDebugUnitTest`

## Code conventions

### TypeScript
- Prettier: 100 char width, single quotes, trailing commas (es5)
- ESLint: extends expo-module-scripts flat config
- No unused locals (enforced by tsconfig `noUnusedLocals: true`)

### Swift
- SwiftFormat: 2-space indent, Swift 5.9 (see `.swiftformat`)
- SwiftLint: default rules (see `.swiftlint.yml`)
- Requires `brew install swiftlint swiftformat`

### Kotlin
- ktlint with `android_studio` code style (see `android/.editorconfig`)
- 4-space indent (Kotlin standard)
- Requires `brew install ktlint`

## Project structure

- `src/` — TypeScript source (view component, types, module stubs)
- `ios/` — Swift native implementation (PDFKit) and XCTest suite (`ios/Tests/`)
- `android/` — Kotlin native implementation (PdfRenderer)
- `example/` — Expo example app for manual testing
- `build/` — compiled output (gitignored)
