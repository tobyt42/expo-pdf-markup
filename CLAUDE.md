# expo-pdf-markup

Expo module for displaying and annotating PDFs on iOS (native PDFKit), with web fallback stub.

## Quality checks

Run all checks: `npm run validate`

Individual commands:
- `npm run typecheck` — TypeScript type checking
- `npm run lint` — ESLint (flat config, ESLint 9)
- `npm run lint:swift` — SwiftLint on ios/
- `npm run format:check` — Prettier check
- `npm run format:swift:check` — SwiftFormat lint on ios/
- `npm run format` — Prettier auto-fix
- `npm run format:swift` — SwiftFormat auto-fix on ios/
- `npm run test -- --watchAll=false` — Jest tests (runs in iOS, Android, Web, Node projects)
- `npm run test:swift` — XCTest suite for native Swift code (requires simulator)

Always run `npm run validate` before committing.

## Testing

### TypeScript (Jest)
Tests live in `src/__tests__/`. The jest preset (expo-module-scripts) runs 4 projects: iOS, Android, Web, Node.

- Use `.test.native.ts` suffix for tests that only run on iOS/Android
- Use `.test.web.tsx` suffix for tests that only run on Web/Node
- Use plain `.test.ts` for tests that run everywhere
- Mock `expo` in native tests that import the native view (`requireNativeView`)

### Swift (XCTest)
Tests live in `example/ios/expopdfmarkupexampleTests/`. Run with `npm run test:swift`.

- Uses `@testable internal import ExpoPdfMarkup` (explicit access level required by Swift 6)
- Test target is wired via Podfile (`inherit! :search_paths`) and Xcode project
- Test PDF resource is bundled in the test target for `loadPdf` / `goToPage` tests
- To add the test target to a fresh example project, run `ruby example/ios/add_test_target.rb` then `pod install`

## Code conventions

### TypeScript
- Prettier: 100 char width, single quotes, trailing commas (es5)
- ESLint: extends expo-module-scripts flat config
- No unused locals (enforced by tsconfig `noUnusedLocals: true`)

### Swift
- SwiftFormat: 2-space indent, Swift 5.9 (see `.swiftformat`)
- SwiftLint: default rules (see `.swiftlint.yml`)
- Requires `brew install swiftlint swiftformat`

## Project structure

- `src/` — TypeScript source (view component, types, module stubs)
- `ios/` — Swift native implementation (PDFKit)
- `example/` — Expo example app for manual testing
- `build/` — compiled output (gitignored)
