# expo-pdf-markup

Expo module for displaying and annotating PDFs on iOS (native PDFKit), with web fallback stub.

## Quality checks

Run all checks across all platforms:
```
npm run qa
```

Platform-specific QA:
- `npm run qa:ts` — typecheck + test typecheck (`typecheck:tests`) + Prettier (auto-fix) + ESLint + actionlint + Jest tests + script tests (`test:scripts`)
- `npm run qa:ios` — SwiftLint + SwiftFormat (auto-fix) + XCTest (requires simulator)
- `npm run qa:android` — ktlint + ktlint --format (auto-fix) + Gradle JUnit tests

Individual commands:
- `npm run typecheck` — TypeScript type checking
- `npm run typecheck:tests` — strict TypeScript type checking of the test suites (`tsconfig.test.json`)
- `npm run lint` / `npm run lint:swift` / `npm run lint:kotlin` — linting per platform
- `npm run lint:workflows` — actionlint on `.github/workflows/` (skipped with a warning locally if actionlint isn't installed; required in CI)
- `npm run format` / `npm run format:swift` / `npm run format:kotlin` — auto-fix formatting
- `npm run format:check` / `npm run format:swift:check` / `npm run format:kotlin:check` — check formatting
- `npm run test` / `npm run test:swift` / `npm run test:kotlin` — tests per platform
- `npm run test:scripts` — Node test runner (`node --test`) for `scripts/**/*.test.mjs`

Always run `npm run qa` (or at minimum `npm run qa:ts`) before committing.

## Releasing

This project uses [Changesets](https://github.com/changesets/changesets) to manage versioning and changelogs.

**When making a change that should be released:**
```
npm run changeset:add
```
Follow the prompts to describe the change and select the semver bump type. Commit the generated `.changeset/*.md` file with your code changes.

**When ready to cut a release:**
```
npm run changeset:version   # bumps package.json, updates CHANGELOG.md, deletes the changeset files
git add -A && git commit -m "chore: release vX.Y.Z"
npm run release             # publishes to npm, pushes git tag, creates GitHub release
```

`npm run release` requires:
- `npm` to be logged in (`npm whoami`)
- `gh` to be authenticated (`gh auth status`)
- A clean working tree on `main`

## Repository settings

The repository's security settings are code: `scripts/repo-settings.mjs` compares the live settings with the desired state in `scripts/repo-settings/desired-state.mjs` and can put them back. It manages:
- the `main` ruleset (no deletion or force-push, pull request required with 0 approvals, the four validation job names above as required checks) and the Release tag ruleset on `refs/tags/v*` (creation, update and deletion restricted). Only the Repository admin role can bypass either
- immutable releases
- Actions: allowed actions limited to GitHub's own plus an explicit third-party list, read-only default workflow token that can't approve pull requests, approval required for workflows from all outside contributors
- the `npm-publish` environment (no reviewer, admins can't bypass, deployments only from `main` and `v*` tags) and the `github-pages` deployment policy (`main` and `v*` tags)

```
npm run settings:check     # read-only: lists every difference, exits 1 on drift
npm run settings:apply     # sends only the changes --check reports, then checks again
node scripts/repo-settings.mjs --snapshot   # read-only: prints the live settings as JSON
```
- Needs `gh` authenticated as a repository admin. Add `-- --repo owner/name` to target another repository
- `apply` changes live repository settings: agents run it only after the maintainer has explicitly approved it in chat. `--check` and `--snapshot` are safe to run at any time
- Change a setting by editing `desired-state.mjs`, never in the web UI. Adding a third-party action to a workflow means adding it to `patterns_allowed` and applying, or the workflow won't run
- The comparison is pure (`scripts/repo-settings/plan.mjs`) and tested against snapshots in `scripts/repo-settings/fixtures/` with `npm run test:scripts`. Only the fields listed in the desired state are compared; lists must match exactly, in any order

## Testing

### TypeScript (Jest)
Tests live in `src/__tests__/`. `jest.config.cjs` uses jest-expo presets for 4 projects: iOS, Android, Web, Node.

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
- ESLint: extends the public eslint-config-expo flat config
- No unused locals (enforced by tsconfig `noUnusedLocals: true`)

### Swift
- SwiftFormat: 2-space indent, Swift 5.9 (see `.swiftformat`)
- SwiftLint: default rules (see `.swiftlint.yml`)
- Requires `brew install swiftlint swiftformat`

### Kotlin
- ktlint with `android_studio` code style (see `android/.editorconfig`)
- 4-space indent (Kotlin standard)
- Requires `brew install ktlint`

### GitHub Actions workflows
- Linted with actionlint (`npm run lint:workflows`); requires `brew install actionlint` (and `shellcheck` for `run:` steps)
- `validate-web.yml`, `validate-ios.yml` and `validate-android.yml` run on pull requests and manual dispatch, and are reusable (`workflow_call`)
- `release.yml` is the only workflow triggered by a push to `main`; it calls all three validate workflows, so each platform is validated exactly once per push. Don't add `push` triggers to the validate workflows
- Job names are required status checks on `main`: don't rename `TypeScript, tests, and web builds`, `PDF browser rendering`, `iOS XCTest` or `Android JUnit` without updating `scripts/repo-settings/desired-state.mjs` and running `npm run settings:apply`

## Project structure

- `src/` — TypeScript source (view component, types, module stubs)
- `ios/` — Swift native implementation (PDFKit) and XCTest suite (`ios/Tests/`)
- `android/` — Kotlin native implementation (PdfRenderer)
- `example/` — Expo example app for manual testing
- `build/` — compiled output (gitignored)

## Agent skills

For the Dependabot queue or a specified dependency PR, use the repository's [dependency-batches skill](.agents/skills/dependency-batches/SKILL.md).

To review the Pending changesets before a Release, the maintainer runs the user-invoked [changeset-review skill](.agents/skills/changeset-review/SKILL.md); start it only when they ask.

To cut a Release, the maintainer runs the user-invoked [release skill](.agents/skills/release/SKILL.md); start it only when they ask.

### Issue tracker

Issues are tracked in GitHub Issues on tobyt42/expo-pdf-markup (via the `gh` CLI). See `docs/agents/issue-tracker.md`.

### Triage labels

Uses the five default triage labels (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
