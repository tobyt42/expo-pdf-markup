# Only CI publishes, via npm trusted publishing

Releases and Snapshots are published to npm only by `.github/workflows/release.yml`, authenticated through npm trusted publishing (OIDC) bound to this repository, that workflow file and the `npm-publish` environment. No npm token exists in GitHub or on any machine, and the package is set to disallow token publishing. A Release is triggered by a Release tag, which only the repository admin can create; a Snapshot is triggered by a push to `main`, which only accepts merged pull requests with passing checks. Because the repository is public, the safety of publishing rests on who can create Release tags and change `main`, not on keeping a secret.

## Considered Options

- **Local `npm publish` with 2FA** (previous process): safe but manual on every release, and not something an agent can drive.
- **Automation token as a repository secret**: a long-lived credential that leaks with any workflow compromise and has to be rotated.
- **Required reviewer on the publish environment**: rejected because merging the Release PR is already the maintainer's approval, and a compromised GitHub session could approve anyway.

## Consequences

Snapshots and Releases deliberately share one workflow file and one trusted publisher configuration, although npm allows several, so there is exactly one path to npm to audit. Renaming or splitting `release.yml` requires updating the npm trusted publisher settings first; npm does not validate those settings until publish time.
