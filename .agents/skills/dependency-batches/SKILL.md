---
name: dependency-batches
description: Review the Dependabot queue or a specified dependency PR for expo-pdf-markup, propose concrete maintenance batches, and validate and merge approved updates.
---

# Dependency batches

With no argument, review the open Dependabot queue in `tobyt42/expo-pdf-markup`. A PR number or URL limits work to that PR; inspect companions for compatibility, and propose an expanded scope before adding them. Investigation and reversible preparation are authorised; merging requires the concrete plan approval below.

## Review and classify

Read [tracker guidance](../../../docs/agents/issue-tracker.md), [Dependabot policy](../../../.github/dependabot.yml), and both npm projects' manifests and lockfiles. The library and `example/` deliberately have independent Expo SDK targets and lockfiles. Evaluate each project's SDK compatibility and the library's public peers separately; identical versions across projects are not a requirement.

Inspect each PR's actual manifest and lockfile diff, direct and resolved transitive old/new versions, upstream release notes, peer requirements, engines, and security advisories/fixed versions. A patch label is not a compatibility guarantee. Prioritise security fixes; held security work needs its exposure, blocker and next action recorded.

Keep a ledger with PR URL, reviewed head SHA, base branch and SHA/merge base, exact resolved changes, risk/security priority, repairs, and check/run links with conclusions. Discover current required checks, [workflows](../../../.github/workflows), selectors and called scripts rather than assuming all green badges cover the change.

Hold breaking public API changes, significant React Native/SDK migrations and repairs wider than the proposed maintenance scope for a maintainer decision. For Expo-family updates, read [Expo maintenance](references/expo.md) before proposing or executing them, including patches.

## Establish applicable evidence

Reuse successful CI only for the reviewed content and a compatible base. Record the tested merge commit as well as the PR head when GitHub validates a merge ref. Check which jobs actually ran and what they exercised. Pending, failed, cancelled, stale or unexplained skipped checks do not establish passing coverage; a selected-out job is acceptable only when its exclusion correctly matches the change. Reassess evidence after repairs, rebases, base changes or bot pushes.

Use current configuration to identify remaining coverage:

- Library/example npm changes need applicable hosted formatting in check mode, lint, typechecking (including tests), existing Jest projects, package/docs builds and example web export, using reproducible installs of both lockfiles.
- Native dependency or native/build-tool impact needs clean generated-project iOS XCTest and Android local JUnit evidence. Jest alone does not cover native behavior. Android local JUnit needs no emulator; iOS must use a suitable available simulator.
- PDF.js changes need a real browser against the exported example and its fixture, using the actual worker and observing completed nonblank PDF canvas rendering separately from annotation overlays. A load callback, mocked Jest or a successful export alone is insufficient. Metro refreshes version-coupled worker/WASM assets during export: review relevant resulting assets and test the fresh output. The ordinary fixture does not establish decoder-specific WASM coverage.
- Actions changes need review of upstream action/runtime changes, validation of affected workflow/scripts, and applicable hosted execution; retain all required checks.

Use standard GitHub-hosted Linux/macOS runners, including for Dependabot; exclude private/self-hosted and paid larger runners. Preserve docs deployment. Distinguish local checks from actual hosted results, and report missing hosted coverage as a gap. Supplement genuine gaps and repairs with focused local checks; avoid repeating applicable green suites, speculative rebases, or pushes solely for duplicate evidence.

## Propose and approve

Keep individual PRs by default. When compatibility requires combining updates or meaningful remaining CI runs can be saved, read [consolidation](references/consolidation.md). Completed CI is sunk cost; reducing PR count alone is insufficient.

Prepare reversible investigations and concrete repair diffs before requesting approval. Use isolated worktrees for edits and preserve existing user work; avoid the shared stash. Present each proposed update/batch with constituent URLs, exact versions and reviewed SHAs, risk/security priority, repairs, applicable evidence links and base, remaining validation, processing order, and held items with reasons/next actions. Identify permitted routine repair, retry and split fallbacks.

Ask once for approval to process and merge that concrete plan. Approval covers the agreed routine repairs, validation and merges without repeated permission requests. Material changes—additional PRs/packages, different targets, breaking APIs, significant SDK migrations, or a wider repair—need an updated reviewable proposal and a maintainer decision before dependent execution. Existing explicit approval remains valid for unchanged scope.

## Execute approved work

1. Diagnose failed checks from logs/reports before repairing or retrying. Keep fixes on the branch that will actually merge. A scratch combination passing with unshipped fixes is not evidence for individual PRs. Review resolved versions and base compatibility again after changes and obtain fresh applicable evidence.
2. Retry identified transient/environment failures with a reason, preferring affected jobs. Hold repeated unexplained or deterministic failures and continue independent approved work; do not rerun unchanged failures hoping for green.
3. Immediately before each merge, fetch live PR head, base/compatibility, mergeability and checks. Confirm all required and applicable evidence still covers that content and base. If the head changed, reassess it before proceeding. Use the repository's allowed merge method with `gh pr merge --match-head-commit <reviewed-sha>` (or equivalent API SHA precondition), respecting merge queues and branch protection. Never use administrative bypass. A queued or auto-merge request is pending until the actual merge is confirmed.
4. Reassess remaining PRs against the updated base after each merge. Preserve relevant main checks and deployment behavior; diagnose failures without silently expanding scope.

Finish with linked **merged**, **held**, and **failed** outcomes, versions, repairs, CI evidence and exact next actions. Include superseded PR/replacement links when relevant. Remove only session-created worktrees/branches whose work is safely preserved. This workflow does not authorise package publication, SDK migration, deployment changes or branch-protection changes.
