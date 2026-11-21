# expo-pdf-markup

Displaying PDFs and letting people mark them up, with annotations exchanged as JSON shared by the iOS, Android and web implementations, and releasing the library to npm.

**Host app**:
The app that embeds this library and stores its annotation sets, such as the Choir App.
_Avoid_: consumer (outside the term Consumer-visible change), client app

## Annotations

**Annotation set**:
The full collection of annotations for one document, exchanged as a single JSON string.
_Avoid_: markup set, annotations blob

**Ink stroke**:
One continuous freehand line within an ink annotation, made of ordered ink points.
_Avoid_: path (when meaning a single stroke), line

**Ink point**:
One position on an ink stroke, in visible-page PDF points with y increasing upwards.
_Avoid_: vertex, coordinate pair

**Clean-up**:
What happens to ink points only when an annotation set is written: each coordinate is rounded to 0.1 pt, consecutive duplicate ink points in an ink stroke are dropped, and a stroke of two or more points keeps at least two. Ink points in memory, and every other field, are untouched.
_Avoid_: compression, simplification, normalisation

**Ink point format**:
How an ink point is written in an annotation set: object form or array form. Readers accept either, point by point.
_Avoid_: compact encoding, ink encoding

**Object form**:
The ink point format `{"x": …, "y": …}`, and the default.
_Avoid_: legacy format

**Array form**:
The ink point format `[x, y]`, chosen when the host app opts in.
_Avoid_: compact format, tuple format

## Releasing

**Changeset**:
A small file describing one Consumer-visible change and its semver bump, waiting to be included in the next Release.
_Avoid_: Release note, changelog entry

**Consumer-visible change**:
A change that a Host app, or the developers building one, can observe in the package: its public API or behaviour, native code, dependency ranges, the Expo SDK and React Native versions it is tested against, or the contents of the published package. Only these get a Changeset.
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
A prerelease published automatically from `main` under the `next` dist-tag while there are Pending changesets. Its version is `<latest Release version>-next.<UTC timestamp>` (e.g. `2.0.0-next.20261121190000`), so it sorts below `latest` and never becomes it.
_Avoid_: Canary, nightly, beta, prerelease (when Snapshot is meant)
