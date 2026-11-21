// Tests for the repository settings plan: given the desired state and a snapshot of the live
// settings (fixture JSON, no network), which differences are reported and which requests
// `apply` would send.
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { desiredState } from '../desiredState.ts';
import {
  planChanges,
  type LiveEnvironment,
  type LiveRuleset,
  type Ruleset,
  type SettingChange,
  type Snapshot,
} from '../settingsPlan.ts';

const fixture = (name: string): Snapshot =>
  JSON.parse(readFileSync(resolve(__dirname, `../fixtures/${name}.json`), 'utf8')) as Snapshot;

const settingsWithChanges = (plan: SettingChange[]) => plan.map((change) => change.setting);

/** The planned change to one setting; fails the test when that setting has none. */
function changeTo(plan: SettingChange[], setting: string): SettingChange {
  const change = plan.find((candidate) => candidate.setting === setting);
  if (!change) throw new Error(`no change planned for ${setting}`);
  return change;
}

function ruleset(snapshot: Snapshot, name: string): LiveRuleset {
  const found = snapshot.rulesets.find((candidate) => candidate.name === name);
  if (!found) throw new Error(`no ruleset named ${name}`);
  return found;
}

/** The required status check list of a ruleset, as GitHub stores it. */
function statusChecks(ruleset: Ruleset): { context: string }[] {
  const rule = ruleset.rules.find((candidate) => candidate.type === 'required_status_checks');
  return (rule?.parameters?.required_status_checks ?? []) as { context: string }[];
}

function npmPublish(snapshot: Snapshot): LiveEnvironment {
  const found = snapshot.environments['npm-publish'];
  if (!found) throw new Error('no npm-publish environment');
  return found;
}

const requiredChecks = (ruleset: Ruleset) => statusChecks(ruleset).map((check) => check.context);

describe('planChanges against the settings before the lockdown', () => {
  const plan = planChanges(desiredState, fixture('before-lockdown'));

  it('switches on immutable releases', () => {
    const change = changeTo(plan, 'Immutable releases');
    expect(change.differences).toEqual(['enabled: expected true, found false']);
    expect(change.requests).toEqual([{ method: 'PUT', path: 'immutable-releases' }]);
  });

  it('limits Actions to the allowed list, enabling the list after selecting it', () => {
    const allowed = changeTo(plan, 'Actions: allowed actions');
    expect(allowed.differences).toEqual(['allowed_actions: expected "selected", found "all"']);
    expect(allowed.requests).toEqual([
      {
        method: 'PUT',
        path: 'actions/permissions',
        body: { enabled: true, allowed_actions: 'selected' },
      },
    ]);

    // GitHub answers 409 for the list while all actions are allowed, so there is no list yet.
    const list = changeTo(plan, 'Actions: allowed actions list');
    expect(list.differences).toEqual(['no list yet (all actions are allowed)']);
    expect(list.requests).toEqual([
      {
        method: 'PUT',
        path: 'actions/permissions/selected-actions',
        body: {
          github_owned_allowed: true,
          verified_allowed: false,
          patterns_allowed: [
            'android-actions/setup-android@*',
            'gradle/actions/setup-gradle@*',
            'ruby/setup-ruby@*',
          ],
        },
      },
    ]);
    const settings = settingsWithChanges(plan);
    expect(settings.indexOf('Actions: allowed actions')).toBeLessThan(
      settings.indexOf('Actions: allowed actions list')
    );
  });

  it('requires approval for workflows from all outside contributors', () => {
    const change = changeTo(plan, 'Actions: outside contributor approval');
    expect(change.differences).toEqual([
      'approval_policy: expected "all_external_contributors", found "first_time_contributors"',
    ]);
    expect(change.requests).toEqual([
      {
        method: 'PUT',
        path: 'actions/permissions/fork-pr-contributor-approval',
        body: { approval_policy: 'all_external_contributors' },
      },
    ]);
  });

  it('extends the existing main ruleset in place', () => {
    const change = changeTo(plan, 'Ruleset "Protect main from accidents"');
    expect(change.differences).toEqual([
      'bypass_actors: expected [{"actor_id":5,"actor_type":"RepositoryRole","bypass_mode":"always"}], found []',
      'rules: missing pull_request',
      'rules: missing required_status_checks',
    ]);
    expect(change.requests).toEqual([
      { method: 'PUT', path: 'rulesets/21795519', body: expect.any(Object) },
    ]);
    const body = change.requests[0]?.body as Ruleset;
    expect(body.rules.map((rule) => rule.type)).toEqual([
      'deletion',
      'non_fast_forward',
      'pull_request',
      'required_status_checks',
    ]);
    expect(requiredChecks(body)).toEqual([
      'TypeScript, tests, and web builds',
      'PDF browser rendering',
      'iOS XCTest',
      'Android JUnit',
    ]);
  });

  it('creates the Release tag ruleset that only the admin role can bypass', () => {
    const change = changeTo(plan, 'Ruleset "Release tags"');
    expect(change.differences).toEqual(['ruleset does not exist']);
    expect(change.requests).toEqual([
      {
        method: 'POST',
        path: 'rulesets',
        body: {
          name: 'Release tags',
          target: 'tag',
          enforcement: 'active',
          conditions: { ref_name: { include: ['refs/tags/v*'], exclude: [] } },
          bypass_actors: [{ actor_id: 5, actor_type: 'RepositoryRole', bypass_mode: 'always' }],
          rules: [{ type: 'creation' }, { type: 'update' }, { type: 'deletion' }],
        },
      },
    ]);
  });

  it('creates the npm-publish environment limited to main and v* tags', () => {
    const change = changeTo(plan, 'Environment "npm-publish"');
    expect(change.differences).toEqual(['environment does not exist']);
    expect(change.requests).toEqual([
      {
        method: 'PUT',
        path: 'environments/npm-publish',
        body: {
          can_admins_bypass: false,
          reviewers: [],
          wait_timer: 0,
          deployment_branch_policy: { protected_branches: false, custom_branch_policies: true },
        },
      },
      {
        method: 'POST',
        path: 'environments/npm-publish/deployment-branch-policies',
        body: { name: 'main', type: 'branch' },
      },
      {
        method: 'POST',
        path: 'environments/npm-publish/deployment-branch-policies',
        body: { name: 'v*', type: 'tag' },
      },
    ]);
  });

  it('limits the github-pages deployment policy to v* tags, adding them before removing main', () => {
    const change = changeTo(plan, 'Environment "github-pages"');
    expect(change.differences).toEqual([
      'deployment policy: missing tag "v*"',
      'deployment policy: unexpected branch "main"',
    ]);
    expect(change.requests).toEqual([
      {
        method: 'POST',
        path: 'environments/github-pages/deployment-branch-policies',
        body: { name: 'v*', type: 'tag' },
      },
      {
        method: 'DELETE',
        path: 'environments/github-pages/deployment-branch-policies/44390415',
      },
    ]);
  });

  it('leaves the already read-only workflow token alone', () => {
    expect(settingsWithChanges(plan)).not.toContain('Actions: workflow token');
  });
});

describe('planChanges against settings already in the desired state', () => {
  // As GitHub returns them: extra metadata and defaults, lists in its own order.
  const compliant = fixture('after-lockdown');

  it('finds nothing to change, so a second apply sends no requests', () => {
    expect(planChanges(desiredState, compliant)).toEqual([]);
  });
});

describe('planChanges reports drift from the desired state', () => {
  const drifted = (mutate: (snapshot: Snapshot) => void) => {
    const snapshot = fixture('after-lockdown');
    mutate(snapshot);
    return planChanges(desiredState, snapshot);
  };

  it('reports an app added as a Release tag bypass actor', () => {
    const plan = drifted((s) =>
      ruleset(s, 'Release tags').bypass_actors.push({
        actor_id: 29110,
        actor_type: 'Integration',
        bypass_mode: 'always',
      })
    );
    expect(settingsWithChanges(plan)).toEqual(['Ruleset "Release tags"']);
    expect(plan[0]?.differences[0]).toMatch(/^bypass_actors: expected .* found .*Integration/);
  });

  it('reports a required check that was removed from main', () => {
    const plan = drifted((s) => {
      const checks = statusChecks(ruleset(s, 'Protect main from accidents'));
      checks.splice(
        checks.findIndex((c) => c.context === 'iOS XCTest'),
        1
      );
    });
    expect(settingsWithChanges(plan)).toEqual(['Ruleset "Protect main from accidents"']);
    expect(plan[0]?.differences[0]).toMatch(
      /^rules\.required_status_checks\.required_status_checks: /
    );
  });

  it('reports a rule that is not in the desired state', () => {
    const plan = drifted((s) =>
      ruleset(s, 'Release tags').rules.push({ type: 'non_fast_forward' })
    );
    expect(plan[0]?.differences).toEqual(['rules: unexpected non_fast_forward']);
  });

  it('reports a required reviewer on npm-publish and puts the environment back', () => {
    const plan = drifted((s) =>
      npmPublish(s).environment.protection_rules.push({
        id: 1,
        type: 'required_reviewers',
        prevent_self_review: false,
        reviewers: [{ type: 'User', reviewer: { id: 42, login: 'someone' } }],
      })
    );
    expect(plan[0]?.differences).toEqual([
      'reviewers: expected [], found [{"type":"User","id":42}]',
    ]);
    expect(plan[0]?.requests[0]?.method).toBe('PUT');
    expect(plan[0]?.requests[0]?.path).toBe('environments/npm-publish');
  });

  it('deletes an extra deployment policy on npm-publish', () => {
    const plan = drifted((s) =>
      npmPublish(s).branchPolicies.push({ id: 777, name: 'feat/*', type: 'branch' })
    );
    expect(plan[0]?.differences).toEqual(['deployment policy: unexpected branch "feat/*"']);
    expect(plan[0]?.requests).toEqual([
      { method: 'DELETE', path: 'environments/npm-publish/deployment-branch-policies/777' },
    ]);
  });

  it('ignores the order GitHub returns the allowed actions in', () => {
    expect(drifted((s) => s.selectedActions?.patterns_allowed.reverse())).toEqual([]);
  });

  it('reports a workflow token that can approve pull requests', () => {
    const plan = drifted((s) => (s.workflowPermissions.can_approve_pull_request_reviews = true));
    expect(plan[0]?.differences).toEqual([
      'can_approve_pull_request_reviews: expected false, found true',
    ]);
  });
});
