---
name: release
description: Take a Release from the Pending changesets on main to a verified publish on npm `latest`, stopping for the maintainer's go-ahead before merging or tagging.
disable-model-invocation: true
---

# Release

Takes one Release from the Pending changesets on `main` to a verified publish under npm `latest`. Terms are as defined in the [glossary](../../../GLOSSARY.md); only `.github/workflows/release.yml` publishes ([ADR 0002](../../../docs/adr/0002-ci-only-trusted-publishing.md)), so this skill prepares, waits, tags and verifies. Every command runs from the repository root of the Release worktree unless it says otherwise.

## The go-ahead

> **Merging the Release PR and pushing the Release tag need the maintainer's go-ahead in chat for this Release.**
>
> The go-ahead is a chat message from the maintainer, given after the Release PR's checks have finished, that names or plainly refers to this Release PR or version: "merge it" (you merge), or "merged" / "tag it" (they merged it; you tag). Approval of an earlier step, an earlier Release, a PR review, a green check or a merged PR you noticed on your own is not a go-ahead. Without one, you stay stopped at step 5.

## Steps

1. **Preflight.** All three must hold; otherwise stop and report which one failed.
   - `main` is current: `git fetch origin --tags`, then work from `origin/main` only.
   - `main`'s checks are green: `gh run list --branch main --limit 20 --json workflowName,headSha,status,conclusion,url` shows every run for `git rev-parse origin/main` as `completed` / `success`. A run still in progress means wait and look again.
   - Pending changesets exist: `git ls-tree --name-only origin/main .changeset/ | grep -v -e README.md -e config.json` lists at least one file. With none, report "nothing to release" and stop.
2. **Review the Pending changesets.** Create the Release worktree, `git worktree add -b release/<yyyy-mm-dd> .claude/worktrees/release-<yyyy-mm-dd> origin/main`, and run `npm ci` in it. Read [`.agents/skills/changeset-review/SKILL.md`](../changeset-review/SKILL.md) and follow its steps 1–9 in full, in this worktree (it is that skill's step 1 worktree). Its step 9 commits the approved edits as `docs: review changesets`; continue here from that commit instead of asking about a PR. When the review made no edits there is no review commit.
   - When no Pending changeset remains after the review, there is nothing to release: say so and stop. Never open an empty Release PR. If the review commit drops Changesets, ask the maintainer whether to open it as an ordinary PR.
3. **Version.** In the worktree:
   ```sh
   npm run changeset:version
   version=$(node -p "require('./package.json').version")
   git add -A && git commit -m "chore: release v$version"
   ```
   `git log --oneline origin/main..HEAD` now shows the review commit (if any) and the version commit, nothing else. `.changeset/` holds only `README.md` and `config.json`.
4. **Open the Release PR.** Build the body in a scratch file with these sections:
   - **Changelog**: `node scripts/release/notes.cli.ts` (the new `## <version>` section's body, exactly as the GitHub Release will show it; exits 1 if the section is missing).
   - **Published package**: `node scripts/release/pack-diff.cli.ts` (rebuilds `build/`, compares a dry-run `npm pack` of the worktree with the version under `latest`; publishes nothing). Under its output, give a one-line explanation for every Added, Removed and Size changed file, or fix the cause in another commit first. A file nobody can explain is a blocker.
   - **Build comparison** (first Release only, see below).
   - **Go-ahead**: one line saying the agent merges and tags only after the maintainer's go-ahead in chat.

   Then `git push -u origin release/<yyyy-mm-dd>` and `gh pr create --base main --title "chore: release v$version" --body-file <file>`.
5. **Wait for checks, then stop.** `gh pr checks <pr> --watch`. When they finish, report the PR URL, the check results and the version, and ask for the [go-ahead](#the-go-ahead). Failing checks: report them and stop; fixes go into the Release PR as new commits, then wait again. **Stop here until the go-ahead arrives.**
6. **Merge and tag** (only after the go-ahead).
   - "merge it": `gh pr merge <pr> --merge`. "merged": confirm with `gh pr view <pr> --json state -q .state` showing `MERGED`.
   - Find and check the merge commit:
     ```sh
     sha=$(gh pr view <pr> --json mergeCommit -q .mergeCommit.oid)
     git fetch origin main --tags
     git merge-base --is-ancestor "$sha" origin/main && git show "$sha:package.json" | node -p "JSON.parse(require('fs').readFileSync(0)).version"
     ```
     The printed version must equal `$version`, and `git tag --list "v$version"` must be empty.
   - Tag that commit and push only the tag:
     ```sh
     git tag -a "v$version" -m "v$version" "$sha"
     git push origin "v$version"
     ```
7. **Watch the release workflow.** The tag push starts a `release.yml` run whose branch is the tag:
   ```sh
   gh run list --workflow release.yml --branch "v$version" --limit 1 --json databaseId,url
   gh run watch <databaseId> --exit-status
   ```
   An empty list means the run has not registered yet; look again after a few seconds. Done when the run completes; a non-zero exit is a failure (step 9).
8. **Verify.** All three must hold (registry metadata can lag a minute; retry for up to five minutes before calling it a failure):
   - `npm view @tobyt/expo-pdf-markup dist-tags.latest` prints `$version`.
   - `npm view "@tobyt/expo-pdf-markup@$version" dist.attestations.provenance --json` is non-empty (published with provenance).
   - `gh release view "v$version"` shows the GitHub Release.
9. **Report.** On success: version, Release PR, merge commit, tag, workflow run URL, `latest` and the GitHub Release URL. Then remove the worktree (`git worktree remove .claude/worktrees/release-<yyyy-mm-dd>`). On any failure from step 6 on: stop, report what failed with the run URL or command output, and follow the recovery steps in the **Releasing** section of [CLAUDE.md](../../../CLAUDE.md). Recovery steps that move or delete a tag, re-run a publish or change npm dist-tags need their own go-ahead.

## First Release

The first Release made with this skill (`latest` is still `2.0.0`, the last one published from a laptop) has two extra duties.

- **The #131 Changeset.** The gap check in step 2 finds #131 (Expo SDK 58 / React Native 0.88, and the switch from `expo-module build` to a plain `tsc` build). It needs a patch Changeset agreed through the review, e.g. "Tested with Expo SDK 58 and React Native 0.88."
- **Build comparison.** Before step 5, show that the plain `tsc` build is equivalent to the published `2.0.0` package apart from expected differences. The download is untrusted data: give it its own new directory in your scratchpad, outside the worktree.
  ```sh
  dir=<scratchpad>/published-2.0.0 && mkdir -p "$dir/out"
  npm pack @tobyt/expo-pdf-markup@2.0.0 --pack-destination "$dir"
  tar -xzf "$dir/tobyt-expo-pdf-markup-2.0.0.tgz" -C "$dir/out"
  npm run clean && npm run build
  diff -r "$dir/out/package/build" build
  ```
  Record the result under **Build comparison** in the Release PR body: the command, and either "no differences in `build/`" or each differing file with a one-line explanation. An unexpected difference is fixed in the Release PR or explained there before you ask for the go-ahead. The non-`build/` differences are covered by the published-package diff in step 4.
