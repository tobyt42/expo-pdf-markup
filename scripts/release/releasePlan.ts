// Release plan module: decides what the publish job in .github/workflows/release.yml does.
//
// Pure: it takes plain facts collected by the CI wrapper (plan.cli.ts) and returns a plan. It
// never reads files, runs git or calls npm, so every decision is covered by Jest tests.
// See GLOSSARY.md (Releasing) for the terms used here.
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
  /** The current time; Snapshot versions (`0.0.0-next.<UTC timestamp>`) use it. */
  now: Date;
}

export type ReleasePlan =
  | { action: 'skip'; reason: string }
  | { action: 'snapshot'; version: string; distTag: 'next' }
  | { action: 'release'; version: string; distTag: 'latest'; notes: string }
  | { action: 'refuse'; reason: string };

/**
 * The plan as `$GITHUB_OUTPUT` values for the later jobs in release.yml. `publish` is `true`
 * exactly when the publish job should run, so the workflow tests one flag, not each action.
 */
export function planOutputs(plan: ReleasePlan): Record<string, string> {
  if (plan.action === 'skip' || plan.action === 'refuse') {
    return { action: plan.action, publish: 'false' };
  }
  const outputs: Record<string, string> = {
    action: plan.action,
    publish: 'true',
    version: plan.version,
    'dist-tag': plan.distTag,
  };
  if (plan.action === 'release') outputs.notes = plan.notes;
  return outputs;
}

const MAIN_REF = 'refs/heads/main';
const TAG_PREFIX = 'refs/tags/';
/** Release tags are `v<version>`; other tags never publish. */
const RELEASE_TAG_PREFIX = `${TAG_PREFIX}v`;

/**
 * Every Snapshot is `0.0.0-next.<UTC timestamp>`. The bump types can still change in the
 * changeset review, so a Snapshot doesn't predict the next Release's version. The placeholder
 * also sorts below every Release, so a Snapshot can never outrank `latest`.
 */
const SNAPSHOT_BASE = '0.0.0';

export function planRelease(facts: ReleaseFacts): ReleasePlan {
  if (facts.ref === MAIN_REF) return planSnapshot(facts);
  if (facts.ref.startsWith(RELEASE_TAG_PREFIX)) return planFromReleaseTag(facts);
  return {
    action: 'skip',
    reason: `${facts.ref} is not main or a Release tag, so there is nothing to publish`,
  };
}

/** The Release checks, in order; the first one that fails refuses the Release. */
function planFromReleaseTag(facts: ReleaseFacts): ReleasePlan {
  const tag = facts.ref.slice(TAG_PREFIX.length);
  const version = facts.packageVersion;
  if (tag !== `v${version}`) {
    return {
      action: 'refuse',
      reason: `tag check failed: ${tag} does not match package.json, whose version ${version} needs the tag v${version}`,
    };
  }
  if (!facts.commitOnMain) {
    return {
      action: 'refuse',
      reason: `main check failed: the commit tagged ${tag} is not on main`,
    };
  }
  if (facts.pendingChangesets.length > 0) {
    const ids = facts.pendingChangesets.map(({ id }) => id).join(', ');
    return {
      action: 'refuse',
      reason: `Pending changesets check failed: a merged Release PR leaves none, but these remain: ${ids}. Tag the Release PR's merge commit`,
    };
  }
  if (facts.versionPublished) {
    return {
      action: 'refuse',
      reason: `npm check failed: ${version} is already on npm; never reuse a version, release a new one`,
    };
  }
  const notes = releaseNotes(facts.changelog, version);
  if (notes === null) {
    return {
      action: 'refuse',
      reason: `changelog check failed: CHANGELOG.md has no "## ${version}" section with release notes`,
    };
  }
  return { action: 'release', version, distTag: 'latest', notes };
}

/**
 * The body of the changelog section headed `## <version>`, up to the next `## ` heading,
 * without the blank lines around it. Null when there is no such section or it is empty.
 */
export function releaseNotes(changelog: string, version: string): string | null {
  const lines = changelog.split(/\r?\n/);
  const start = lines.findIndex((line) => line.trim() === `## ${version}`);
  if (start === -1) return null;
  const rest = lines.slice(start + 1);
  const end = rest.findIndex((line) => /^## /.test(line));
  const notes = (end === -1 ? rest : rest.slice(0, end)).join('\n').trim();
  return notes === '' ? null : notes;
}

function planSnapshot(facts: ReleaseFacts): ReleasePlan {
  if (facts.pendingChangesets.length === 0) {
    return {
      action: 'skip',
      reason: 'main has no Pending changesets, so there is nothing to snapshot',
    };
  }
  if (facts.pendingChangesets.every(({ bump }) => bump === 'none')) {
    return {
      action: 'skip',
      reason: 'the Pending changesets bump no version, so there is nothing to snapshot',
    };
  }
  return {
    action: 'snapshot',
    version: `${SNAPSHOT_BASE}-next.${utcTimestamp(facts.now)}`,
    distTag: 'next',
  };
}

/** `YYYYMMDDHHMMSS` in UTC: fixed width, so later times sort higher as a semver identifier. */
function utcTimestamp(date: Date): string {
  return date
    .toISOString()
    .replace(/\.\d{3}Z$/, '')
    .replace(/\D/g, '');
}
