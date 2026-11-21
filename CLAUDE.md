# expo-pdf-markup

Expo module for displaying and annotating PDFs on iOS (native PDFKit), with web fallback stub.

## Quality checks

Run all checks across all platforms:
```
npm run qa
```

Platform-specific QA:
- `npm run qa:ts` — typecheck + test typecheck (`typecheck:tests`) + Prettier (auto-fix) + ESLint + actionlint + Jest tests (including the script tests)
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

Always run `npm run qa` (or at minimum `npm run qa:ts`) before committing.

## Releasing

This project uses [Changesets](https://github.com/changesets/changesets) to manage versioning and changelogs. Only CI publishes to npm, from `.github/workflows/release.yml`, using npm trusted publishing: there is no npm token and no local publish (see `docs/adr/0002-ci-only-trusted-publishing.md`). Terms (Changeset, Pending changesets, Release, Release PR, Release tag, Snapshot) are defined in `GLOSSARY.md`.

**When making a Consumer-visible change:**
```
npm run changeset:add
```
Follow the prompts to describe the change and select the semver bump type. Commit the generated `.changeset/*.md` file with your code changes.

**Snapshots:** every push to `main` runs web, iOS and Android validation in `release.yml`. If `main` has Pending changesets, it then publishes a Snapshot (`<latest Release version>-next.<UTC timestamp>`, e.g. `2.0.0-next.20261121190000`, based on the `package.json` version, which only the Release PR bumps) under the `next` dist-tag. The version predicts no Release, sorts below `latest` and sorts by time, and Snapshots taken after a Release sort above earlier ones. The release plan refuses a Snapshot when the `package.json` version isn't a stable `X.Y.Z` or is `0.0.0`, since CocoaPods rejects a prerelease of `0.0.0`. Snapshots never become `latest` and never commit anything back.

**Cutting a Release:** the normal route is the `release` skill (`.agents/skills/release/SKILL.md`), which runs these steps in full, builds the Release PR body and stops for the maintainer's go-ahead before merging and tagging. By hand:
1. On a branch off `main`, review the Pending changesets with the `changeset-review` skill and commit any edits as `docs: review changesets`
2. `npm run changeset:version` (consumes the Pending changesets, bumps `package.json`, updates `CHANGELOG.md`), commit as `chore: release vX.Y.Z`, and open the Release PR with the review commit (if any) and this one
3. The maintainer merges the Release PR; merging is the approval
4. Tag the merge commit on `main` and push the tag (only the maintainer can create Release tags):
   ```
   git tag -a vX.Y.Z -m vX.Y.Z <merge commit> && git push origin vX.Y.Z
   ```
5. `release.yml` runs validation, then the Release checks. It refuses, naming the failed check, when the tag isn't `v` + the `package.json` version, the commit isn't on `main`, Pending changesets remain, the version is already on npm or `CHANGELOG.md` has no section for it. Otherwise it publishes to `latest` with provenance, creates the GitHub Release (title `vX.Y.Z`, notes from the changelog section) and deploys the docs site and web demo to GitHub Pages. Docs deploy only from Releases, never from pushes to `main`
6. Check that `npm view @tobyt/expo-pdf-markup dist-tags.latest` shows the version and that the GitHub Release exists

The decisions live in the release plan module (`scripts/release/releasePlan.ts`, Jest-tested). Dry run it read-only, after `git fetch origin`: `GITHUB_REF=refs/tags/vX.Y.Z node scripts/release/plan.cli.ts`. `node scripts/release/notes.cli.ts` prints the Release notes for the `package.json` version, and `node scripts/release/pack-diff.cli.ts` compares a dry-run pack with the version under `latest`.

**Recovery:**
- **Release tag pushed but the publish failed before reaching npm:** fix the cause if needed, then re-run the failed jobs of the `release.yml` run (`gh run rerun <run-id> --failed`). Don't move the tag
- **Release tag on the wrong commit and nothing published:** the maintainer deletes the tag using the admin bypass (`git push origin :refs/tags/vX.Y.Z`, then `git tag -d vX.Y.Z` locally) and tags the right commit again
- **Bad version already on npm:** never reuse or unpublish it. Fix forward with a patch Release, and `npm deprecate @tobyt/expo-pdf-markup@X.Y.Z "<reason>"` the bad version if needed

## Repository settings

The repository's security settings are code: `scripts/repo-settings/settings.cli.ts` compares the live settings with the desired state in `scripts/repo-settings/desiredState.ts` and can put them back. It manages:
- the `main` ruleset (no deletion or force-push, pull request required with 0 approvals, the four validation job names above as required checks) and the Release tag ruleset on `refs/tags/v*` (creation, update and deletion restricted). Only the Repository admin role can bypass either
- immutable releases
- Actions: allowed actions limited to GitHub's own plus an explicit third-party list, read-only default workflow token that can't approve pull requests, approval required for workflows from all outside contributors
- the `npm-publish` environment (no reviewer, admins can't bypass, deployments only from `main` and `v*` tags) and the `github-pages` deployment policy (`v*` tags only, as docs deploy only from Releases)

```
npm run settings:check     # read-only: lists every difference, exits 1 on drift
npm run settings:apply     # sends only the changes --check reports, then checks again
node scripts/repo-settings/settings.cli.ts --snapshot   # read-only: prints the live settings as JSON
```
- Needs `gh` authenticated as a repository admin. Add `-- --repo owner/name` to target another repository
- `apply` changes live repository settings: agents run it only after the maintainer has explicitly approved it in chat. `--check` and `--snapshot` are safe to run at any time
- Change a setting by editing `desiredState.ts`, never in the web UI. Adding a third-party action to a workflow means adding it to `patterns_allowed` and applying, or the workflow won't run
- The comparison is pure (`scripts/repo-settings/settingsPlan.ts`) and Jest-tested against snapshots in `scripts/repo-settings/fixtures/`. Only the fields listed in the desired state are compared; lists must match exactly, in any order

## Testing

### TypeScript (Jest)
Library tests live in `src/__tests__/`; tests for the repository scripts live in `scripts/release/__tests__/` and `scripts/repo-settings/__tests__/`. `jest.config.cjs` uses jest-expo presets for 4 projects: iOS, Android, Web, Node. The script directories are roots of the Node project only.

- Use `.test.native.ts` suffix for tests that only run on iOS/Android
- Use `.test.web.tsx` suffix for tests that only run on Web/Node
- Use plain `.test.ts` for tests that run everywhere
- Use `.test.node.ts` suffix for the script tests, which only run on Node
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
- Pin every `uses:` to a full commit SHA with its version as a comment (`@<sha> # v7.0.1`); the validate workflows also run inside Releases. Dependabot updates the pins
- Job names are required status checks on `main`: don't rename `TypeScript, tests, and web builds`, `PDF browser rendering`, `iOS XCTest` or `Android JUnit` without updating `scripts/repo-settings/desiredState.ts` and running `npm run settings:apply`

## Project structure

- `src/` — TypeScript source (view component, types, module stubs)
- `ios/` — Swift native implementation (PDFKit) and XCTest suite (`ios/Tests/`)
- `android/` — Kotlin native implementation (PdfRenderer)
- `example/` — Expo example app for manual testing
- `scripts/` — repository tooling, never published; `scripts/release/` and `scripts/repo-settings/` are TypeScript that Node 24 runs directly (CLI entry points end in `.cli.ts`, shared helpers in `scripts/lib/`)
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
