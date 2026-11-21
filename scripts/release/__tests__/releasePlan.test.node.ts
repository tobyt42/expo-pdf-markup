import semverCompare from 'semver/functions/compare.js';

import { planOutputs, planRelease, releaseNotes, type ReleaseFacts } from '../releasePlan.ts';

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
  it('plans a Snapshot with a 0.0.0 placeholder version when there are Pending changesets', () => {
    expect(
      planRelease(facts({ pendingChangesets: [{ id: 'calm-dogs-sing', bump: 'patch' }] }))
    ).toEqual({ action: 'snapshot', version: '0.0.0-next.20261121090507', distTag: 'next' });
  });

  it('skips when there are no Pending changesets', () => {
    expect(planRelease(facts({ pendingChangesets: [] }))).toEqual({
      action: 'skip',
      reason: expect.stringContaining('no Pending changesets'),
    });
  });

  it.each([
    ['patch', [{ id: 'a', bump: 'patch' }]],
    [
      'major',
      [
        { id: 'a', bump: 'minor' },
        { id: 'b', bump: 'major' },
      ],
    ],
  ] as const)(
    'does not predict the next Release from the bump types (%s)',
    (_, pendingChangesets) => {
      expect(planRelease(facts({ pendingChangesets: [...pendingChangesets] }))).toEqual({
        action: 'snapshot',
        version: '0.0.0-next.20261121090507',
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

  it('gives Snapshots taken at increasing times increasing semver order, whatever the bumps', () => {
    // The bumps change between Snapshots, as a changeset review can reclassify them.
    const snapshots = [
      ['2026-11-21T09:05:07Z', 'minor'],
      ['2026-11-21T09:05:08Z', 'patch'],
      ['2026-11-21T10:00:00Z', 'major'],
      ['2026-12-01T00:00:00Z', 'patch'],
      ['2027-01-01T00:00:00Z', 'minor'],
    ] as const;
    const versions = snapshots.map(([time, bump]) => {
      const plan = planRelease(
        facts({ pendingChangesets: [{ id: 'a', bump }], now: new Date(time) })
      );
      if (plan.action !== 'snapshot') throw new Error(`expected a snapshot, got ${plan.action}`);
      return plan.version;
    });
    expect([...versions].reverse().sort(semverCompare)).toEqual(versions);
    // A Snapshot sorts below every Release, so it can never outrank latest.
    expect(semverCompare(versions[versions.length - 1]!, '0.0.1')).toBe(-1);
  });
});

describe('planRelease elsewhere', () => {
  it('skips a push to another branch, even with Pending changesets', () => {
    expect(
      planRelease(
        facts({ ref: 'refs/heads/feature', pendingChangesets: [{ id: 'a', bump: 'patch' }] })
      )
    ).toEqual({ action: 'skip', reason: expect.stringContaining('refs/heads/feature') });
  });

  it('skips a tag that is not a Release tag', () => {
    expect(planRelease(facts({ ref: 'refs/tags/docs-2026' }))).toEqual({
      action: 'skip',
      reason: expect.stringContaining('refs/tags/docs-2026'),
    });
  });
});

describe('planRelease on a Release tag', () => {
  const changelog = [
    '# @tobyt/expo-pdf-markup',
    '',
    '## 2.1.0',
    '',
    '',
    '### Minor Changes',
    '',
    '- abc1234: Add a thing.',
    '',
    '  Rebuild your native iOS app to use it.',
    '',
    '### Patch Changes',
    '',
    '- def5678: Fix another thing.',
    '',
    '',
    '## 2.0.0',
    '',
    '### Major Changes',
    '',
    '- 0123456: Something older.',
    '',
  ].join('\n');

  const release = (overrides: Partial<ReleaseFacts> = {}) =>
    facts({
      ref: 'refs/tags/v2.1.0',
      packageVersion: '2.1.0',
      versionPublished: false,
      changelog,
      ...overrides,
    });

  it('plans a Release under latest with the notes of the matching changelog section', () => {
    expect(planRelease(release())).toEqual({
      action: 'release',
      version: '2.1.0',
      distTag: 'latest',
      notes: [
        '### Minor Changes',
        '',
        '- abc1234: Add a thing.',
        '',
        '  Rebuild your native iOS app to use it.',
        '',
        '### Patch Changes',
        '',
        '- def5678: Fix another thing.',
      ].join('\n'),
    });
  });

  it.each(['refs/tags/v2.1.1', 'refs/tags/v2.1', 'refs/tags/v2.1.0-rc.1', 'refs/tags/vnext'])(
    'refuses %s when package.json says 2.1.0',
    (ref) => {
      expect(planRelease(release({ ref }))).toEqual({
        action: 'refuse',
        reason: expect.stringMatching(/^tag check failed: .*v2\.1\.0/),
      });
    }
  );

  it('refuses a tagged commit that is not on main', () => {
    expect(planRelease(release({ commitOnMain: false }))).toEqual({
      action: 'refuse',
      reason: expect.stringMatching(/^main check failed: /),
    });
  });

  it('refuses while Pending changesets remain, naming them and pointing at the Release PR', () => {
    const plan = planRelease(
      release({ pendingChangesets: [{ id: 'calm-dogs-sing', bump: 'patch' }] })
    );
    expect(plan).toEqual({
      action: 'refuse',
      reason: expect.stringMatching(/^Pending changesets check failed: .*calm-dogs-sing/),
    });
    expect(plan).toMatchObject({ reason: expect.stringContaining('Release PR') });
    expect(plan).not.toMatchObject({ reason: expect.stringContaining('version step') });
  });

  it('refuses a version that is already on npm', () => {
    expect(planRelease(release({ versionPublished: true }))).toEqual({
      action: 'refuse',
      reason: expect.stringMatching(/^npm check failed: .*2\.1\.0/),
    });
  });

  it('refuses when the changelog has no section for the version', () => {
    expect(planRelease(release({ ref: 'refs/tags/v2.2.0', packageVersion: '2.2.0' }))).toEqual({
      action: 'refuse',
      reason: expect.stringMatching(/^changelog check failed: .*2\.2\.0/),
    });
  });

  it('takes the notes of an older section up to the next heading', () => {
    const plan = planRelease(release({ ref: 'refs/tags/v2.0.0', packageVersion: '2.0.0' }));
    expect(plan).toMatchObject({
      action: 'release',
      notes: '### Major Changes\n\n- 0123456: Something older.',
    });
  });
});

describe('planOutputs, the plan as the later release.yml jobs read it', () => {
  it('publishes a Snapshot under next', () => {
    expect(
      planOutputs({ action: 'snapshot', version: '2.1.0-next.20261121090507', distTag: 'next' })
    ).toEqual({
      action: 'snapshot',
      publish: 'true',
      version: '2.1.0-next.20261121090507',
      'dist-tag': 'next',
    });
  });

  it('publishes a Release under latest, with its notes', () => {
    expect(
      planOutputs({ action: 'release', version: '2.1.0', distTag: 'latest', notes: '- A thing.' })
    ).toEqual({
      action: 'release',
      publish: 'true',
      version: '2.1.0',
      'dist-tag': 'latest',
      notes: '- A thing.',
    });
  });

  it.each(['skip', 'refuse'] as const)('publishes nothing on %s', (action) => {
    expect(planOutputs({ action, reason: 'because' })).toEqual({ action, publish: 'false' });
  });
});

describe('releaseNotes, the changelog section the Release PR and GitHub Release show', () => {
  const changelog =
    '# pkg\n\n## 2.1.0\n\n### Minor Changes\n\n- Add a thing.\n\n## 2.0.0\n\n- Old.\n';

  it('is the body of the section for the version', () => {
    expect(releaseNotes(changelog, '2.1.0')).toBe('### Minor Changes\n\n- Add a thing.');
  });

  it('is null when the changelog has no section for the version', () => {
    expect(releaseNotes(changelog, '2.2.0')).toBeNull();
  });
});
