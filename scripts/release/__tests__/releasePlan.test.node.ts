import semverCompare from 'semver/functions/compare.js';

import { planRelease, type ReleaseFacts } from '../releasePlan.ts';

const MAIN = 'refs/heads/main';

function facts(overrides: Partial<ReleaseFacts> = {}): ReleaseFacts {
  return {
    ref: MAIN,
    packageVersion: '2.0.0',
    pendingChangesets: [],
    commitOnMain: true,
    versionPublished: true,
    changelog: '# @tobyt/expo-pdf-markup\n\n## 2.0.0\n\n### Major Changes\n\n- Something\n',
    now: new Date('2026-11-21T09:05:07Z'),
    ...overrides,
  };
}

describe('planRelease on main', () => {
  it('plans a Snapshot of the next patch version when Pending changesets are patches', () => {
    expect(
      planRelease(facts({ pendingChangesets: [{ id: 'calm-dogs-sing', bump: 'patch' }] }))
    ).toEqual({ action: 'snapshot', version: '2.0.1-next.20261121090507', distTag: 'next' });
  });

  it('skips when there are no Pending changesets', () => {
    expect(planRelease(facts({ pendingChangesets: [] }))).toEqual({
      action: 'skip',
      reason: expect.stringContaining('no Pending changesets'),
    });
  });

  it.each([
    [
      'minor',
      [
        { id: 'a', bump: 'patch' },
        { id: 'b', bump: 'minor' },
      ],
      '2.1.0',
    ],
    [
      'major',
      [
        { id: 'a', bump: 'minor' },
        { id: 'b', bump: 'major' },
        { id: 'c', bump: 'patch' },
      ],
      '3.0.0',
    ],
  ] as const)(
    'bases the Snapshot on the highest bump (%s) of the Pending changesets',
    (_, pendingChangesets, nextVersion) => {
      expect(planRelease(facts({ pendingChangesets: [...pendingChangesets] }))).toEqual({
        action: 'snapshot',
        version: `${nextVersion}-next.20261121090507`,
        distTag: 'next',
      });
    }
  );

  it('skips when the Pending changesets bump nothing', () => {
    expect(planRelease(facts({ pendingChangesets: [{ id: 'docs-only', bump: 'none' }] }))).toEqual({
      action: 'skip',
      reason: expect.stringContaining('bump'),
    });
  });

  it('gives Snapshots taken at increasing times increasing semver order', () => {
    const times = [
      '2026-11-21T09:05:07Z',
      '2026-11-21T09:05:08Z',
      '2026-11-21T10:00:00Z',
      '2026-12-01T00:00:00Z',
      '2027-01-01T00:00:00Z',
    ];
    const versions = times.map((time) => {
      const plan = planRelease(
        facts({ pendingChangesets: [{ id: 'a', bump: 'patch' }], now: new Date(time) })
      );
      if (plan.action !== 'snapshot') throw new Error(`expected a snapshot, got ${plan.action}`);
      return plan.version;
    });
    expect([...versions].reverse().sort(semverCompare)).toEqual(versions);
    // A Snapshot sorts below the version it previews, so it never outranks that Release.
    expect(semverCompare(versions[0]!, '2.0.1')).toBe(-1);
    expect(semverCompare(versions[0]!, '2.0.0')).toBe(1);
  });

  it.each(['2.1.0-next.20261121090507', 'not-a-version'])(
    'refuses a Snapshot when the package.json version is %s',
    (packageVersion) => {
      expect(
        planRelease(facts({ packageVersion, pendingChangesets: [{ id: 'a', bump: 'patch' }] }))
      ).toEqual({ action: 'refuse', reason: expect.stringContaining('package.json version') });
    }
  );
});

describe('planRelease elsewhere', () => {
  it('skips a push to another branch, even with Pending changesets', () => {
    expect(
      planRelease(
        facts({ ref: 'refs/heads/feature', pendingChangesets: [{ id: 'a', bump: 'patch' }] })
      )
    ).toEqual({ action: 'skip', reason: expect.stringContaining('refs/heads/feature') });
  });

  it('refuses a tag push until Releases are planned', () => {
    expect(planRelease(facts({ ref: 'refs/tags/v2.0.0' }))).toEqual({
      action: 'refuse',
      reason: expect.stringContaining('refs/tags/v2.0.0'),
    });
  });
});
