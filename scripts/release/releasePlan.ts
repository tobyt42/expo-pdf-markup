// Release plan module: decides what the publish job in .github/workflows/release.yml does.
//
// Pure: it takes plain facts collected by the CI wrapper (plan.ts) and returns a plan. It
// never reads files, runs git or calls npm, so every decision is covered by Jest tests.
// See GLOSSARY.md (Releasing) for the terms used here.
import semverInc from 'semver/functions/inc.js';
import semverPrerelease from 'semver/functions/prerelease.js';

/** A Changeset's semver bump for this package, as Changesets records it. */
export type BumpType = 'major' | 'minor' | 'patch' | 'none';

export interface PendingChangeset {
  /** The Changeset's id (its file name without `.md`). */
  id: string;
  bump: BumpType;
}

export interface ReleaseFacts {
  /** The full git ref that was pushed, e.g. `refs/heads/main` or `refs/tags/v2.1.0`. */
  ref: string;
  /** The `version` field of `package.json` at the pushed commit. */
  packageVersion: string;
  /** The Pending changesets at the pushed commit. */
  pendingChangesets: PendingChangeset[];
  /** Whether the pushed commit is reachable from `main`. */
  commitOnMain: boolean;
  /** Whether `packageVersion` already exists on npm. */
  versionPublished: boolean;
  /** The text of `CHANGELOG.md` at the pushed commit. */
  changelog: string;
  /** The current time; Snapshot versions use it in UTC. */
  now: Date;
}

export type ReleasePlan =
  | { action: 'skip'; reason: string }
  | { action: 'snapshot'; version: string; distTag: 'next' }
  | { action: 'release'; version: string; distTag: 'latest'; notes: string }
  | { action: 'refuse'; reason: string };

const MAIN_REF = 'refs/heads/main';
const TAG_PREFIX = 'refs/tags/';

/** Changesets' order of bump types: the highest one across the Pending changesets wins. */
const BUMP_ORDER: readonly BumpType[] = ['none', 'patch', 'minor', 'major'];

export function planRelease(facts: ReleaseFacts): ReleasePlan {
  if (facts.ref === MAIN_REF) return planSnapshot(facts);
  if (facts.ref.startsWith(TAG_PREFIX)) {
    // Release decisions (tag/version/main/Pending changesets/npm checks) come with #147.
    return {
      action: 'refuse',
      reason: `ref check failed: Releases from ${facts.ref} are not supported yet`,
    };
  }
  return { action: 'skip', reason: `${facts.ref} is not main, so there is nothing to publish` };
}

function planSnapshot(facts: ReleaseFacts): ReleasePlan {
  if (facts.pendingChangesets.length === 0) {
    return {
      action: 'skip',
      reason: 'main has no Pending changesets, so there is nothing to snapshot',
    };
  }
  const bump = highestBump(facts.pendingChangesets);
  if (bump === 'none') {
    return {
      action: 'skip',
      reason: 'the Pending changesets bump no version, so there is nothing to snapshot',
    };
  }
  // The version `changeset version` would produce: Changesets applies semver's `inc` with the
  // highest bump, exactly as @changesets/assemble-release-plan does for a single package.
  const nextVersion = semverInc(facts.packageVersion, bump);
  if (nextVersion === null || semverPrerelease(facts.packageVersion) !== null) {
    return {
      action: 'refuse',
      reason: `package.json version check failed: ${JSON.stringify(facts.packageVersion)} is not a stable semver version`,
    };
  }
  return {
    action: 'snapshot',
    version: `${nextVersion}-next.${utcTimestamp(facts.now)}`,
    distTag: 'next',
  };
}

function highestBump(changesets: PendingChangeset[]): BumpType {
  return changesets.reduce<BumpType>(
    (acc, { bump }) => (BUMP_ORDER.indexOf(bump) > BUMP_ORDER.indexOf(acc) ? bump : acc),
    'none'
  );
}

/** `YYYYMMDDHHMMSS` in UTC: fixed width, so later times sort higher as a semver identifier. */
function utcTimestamp(date: Date): string {
  return date
    .toISOString()
    .replace(/\.\d{3}Z$/, '')
    .replace(/\D/g, '');
}
