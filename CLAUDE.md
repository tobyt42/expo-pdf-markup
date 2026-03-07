# expo-pdf-markup

Expo module for displaying and annotating PDFs on iOS (native PDFKit), with web fallback stub.

## Quality checks

Run all checks: `npm run validate`

Individual commands:
- `npm run typecheck` — TypeScript type checking
- `npm run lint` — ESLint (flat config, ESLint 9)
- `npm run format:check` — Prettier check
- `npm run format` — Prettier auto-fix
- `npm run test -- --watchAll=false` — Jest tests (runs in iOS, Android, Web, Node projects)

Always run `npm run validate` before committing.

## Testing

Tests live in `src/__tests__/`. The jest preset (expo-module-scripts) runs 4 projects: iOS, Android, Web, Node.

- Use `.test.native.ts` suffix for tests that only run on iOS/Android
- Use `.test.web.tsx` suffix for tests that only run on Web/Node
- Use plain `.test.ts` for tests that run everywhere
- Mock `expo` in native tests that import the native view (`requireNativeView`)

## Code conventions

- Prettier: 100 char width, single quotes, trailing commas (es5)
- ESLint: extends expo-module-scripts flat config
- No unused locals (enforced by tsconfig `noUnusedLocals: true`)

## Project structure

- `src/` — TypeScript source (view component, types, module stubs)
- `ios/` — Swift native implementation (PDFKit)
- `example/` — Expo example app for manual testing
- `build/` — compiled output (gitignored)
