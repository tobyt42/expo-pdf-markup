---
name: changeset-review
description: Review the Pending changesets with the maintainer, one at a time, and find merged PRs that need a Changeset, before a Release.
disable-model-invocation: true
---

# Changeset review

An editorial pass over the Pending changesets (`.changeset/*.md`, excluding `README.md`) before a Release, followed by a **gap check** for Consumer-visible changes that have no Changeset. Terms are as defined in the [glossary](../../../GLOSSARY.md). Each Changeset ends on the maintainer's **verdict**: keep, rewrite, merge, split or drop.

A Changeset file looks like this; the bump is `patch`, `minor` or `major`:

```md
---
'@tobyt/expo-pdf-markup': patch
---

Text that becomes the changelog entry.
```

## Steps

1. **Open a worktree** before anything is written: a new branch from `origin/main` in its own worktree under `.claude/worktrees/`, never the main checkout. Every write, `git rm` and the final commit happen there.
2. **List the Pending changesets** in filename order: how many there are, the bump each one carries, and the Release they would produce (current `package.json` version plus the highest bump). With none, say so and go to step 6.
3. **Present one Changeset**, then stop and wait for its verdict:
   - its filename, bump type and current text;
   - what actually changed, in a sentence or two, from the PR that added it (`git log --diff-filter=A --format=%H -- <file>`, then `gh pr list --state merged --search <sha>` and `gh pr view <n>`) or the commits;
   - your recommendation, with the exact proposed text and bump type for every file it would write, rename or delete.
4. **Write only approved wording.** When the maintainer pushes back, present the revised wording and wait for approval again; agreeing to a direction is not approving words. Delete a dropped Changeset with `git rm`.
5. Repeat 3–4 until **every Pending changeset has a verdict**. A Changeset merged into an earlier one counts as decided; say so when you reach its turn.
6. **Gap check.** Find the last Release tag (`git tag --list 'v*' --sort=-v:refname | head -1`) and its commit date (`git log -1 --format=%cI <tag>`), then every PR merged into `main` since then: `gh pr list --state merged --base main --search "merged:>=<date>" --limit 200 --json number,title,mergedAt,files`. A PR is **covered** when a Changeset that remains after steps 3–5 was added by it, names it, or was agreed in this review as its entry. Present every uncovered PR in a single table (number, title, files touched, **Consumer-visible** or **not**, one-line reason), classified by the rules under _Consumer-visible or not_.
7. **Decide each Consumer-visible gap** the same way as steps 3–4: one at a time, with the proposed filename, exact text and bump type, then wait for the verdict (add as proposed, rewrite, fold into an existing Changeset, or no Changeset with a reason). The gap check is done when **every uncovered PR is classified and every Consumer-visible one has a verdict**.
8. **Summarise**:
   - a table of the Changesets that remain (file, bump, platforms, the PR or PRs it covers, one-line gist) and the Release they produce;
   - a list of what was dropped or left without a Changeset, with the reason for each.
9. **Commit** the approved edits on the worktree branch as one commit, `docs: review changesets`. When the `release` skill is driving, hand back to it. Otherwise ask the maintainer whether to push and open a PR; versioning and publishing are not part of this skill.

## Consumer-visible or not

A change is Consumer-visible when a developer using the package can observe it (glossary). In this repository that means:

- **Visible**: library code (`src/` outside tests, `ios/` outside `ios/Tests/`, `android/src/main/`, `metro.js`, `metro.d.ts`, `expo-module.config.json`); `dependencies`, `peerDependencies`, `main`, `types` or other resolution fields in the root `package.json`; anything that changes the published file list or the built `build/` output (`.npmignore`, the `build` script, `tsconfig.json` compiler options); the tested Expo SDK or React Native version (a minor or major change to the root `expo` or `react-native` devDependency).
- **Not visible**: other devDependency bumps and lockfile-only changes, `example/`, `scripts/`, `.github/`, tests, the docs site (`typedoc.json`, `docs/`), agent and contributor docs (`CLAUDE.md`, `AGENTS.md`, `.agents/`, `GLOSSARY.md`).

A PR can mix both; it is Consumer-visible if any part is. When the built output might have changed, compare `npm pack --dry-run` in the worktree with `npm view @tobyt/expo-pdf-markup@<last version> dist.tarball` contents before classifying.

## The editorial lens

The readers are developers using the library in their apps. Apply every rule to every Changeset, existing or proposed.

- **Benefit first.** Lead with what the developer gains or has to do, not the mechanism or the internal refactor.
- **Name the public API**: props, types, callbacks, exported functions and the Metro/web plugin (`withPdfMarkup`, `setPdfJsWorkerSrc`), in backticks.
- **Native rebuild.** Always say whether the app needs a new native build ("Rebuild your native iOS app to apply this.").
- **Platform scope.** State which of iOS, Android and web are affected; omit it only when all three are.
- **Breaking means major**: changes to behaviour, coordinates, peer dependency ranges or the minimum supported Expo SDK. Include migration steps.
- **Tested versions.** When the tested Expo SDK or React Native version changes, add a patch Changeset reading "Tested with Expo SDK X and React Native Y."
- **One story per Changeset.** Merge a feature and its follow-up fix; split one Changeset that carries two unrelated changes.
- **Drop** what consumers cannot observe: devDependencies that don't change the output, the example app, scripts, CI, tests and the docs site.
- **British English** (behaviour, colour, serialise).
