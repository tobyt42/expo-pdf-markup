# expo-pdf-markup

An Expo module for displaying and annotating PDFs. This glossary covers the language used for the library itself and for how it is released.

## Releasing

**Changeset**:
A small file describing one Consumer-visible change and its semver bump, waiting to be included in the next Release.
_Avoid_: Release note, changelog entry

**Consumer-visible change**:
A change that developers using the package can observe: its public API or behaviour, native code, dependency ranges, the Expo SDK and React Native versions it is tested against, or the contents of the published package. Only these get a Changeset.
_Avoid_: User-facing change, notable change

**Pending changesets**:
The Changesets on `main` that no Release has consumed yet.

**Release**:
A stable version of the package published to npm under the `latest` dist-tag, with a matching Release tag and GitHub Release.
_Avoid_: Publish, deploy, ship

**Release PR**:
The pull request that consumes the Pending changesets, bumps the version and updates the changelog. Merging it is the maintainer's approval of the Release.
_Avoid_: Version PR, bump PR

**Release tag**:
A `v<version>` git tag on `main` that marks the merged Release PR commit and triggers the Release. Only the maintainer can create one.
_Avoid_: Version tag

**Snapshot**:
A prerelease published automatically from `main` under the `next` dist-tag while there are Pending changesets. It never becomes `latest`.
_Avoid_: Canary, nightly, beta, prerelease (when Snapshot is meant)
