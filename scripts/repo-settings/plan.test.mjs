// Tests for the repository settings plan: given the desired state and a snapshot of the live
// settings (fixture JSON, no network), which differences are reported and which requests
// `apply` would send. Run with `npm run test:scripts`.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { describe, it } from 'node:test';

import { desiredState } from './desired-state.mjs';
import { planChanges } from './plan.mjs';

const fixture = (name) =>
  JSON.parse(readFileSync(new URL(`./fixtures/${name}.json`, import.meta.url), 'utf8'));

const settingsWithChanges = (plan) => plan.map((change) => change.setting);

describe('planChanges against the settings before the lockdown', () => {
  const plan = planChanges(desiredState, fixture('before-lockdown'));

  it('switches on immutable releases', () => {
    const change = plan.find((c) => c.setting === 'Immutable releases');
    assert.deepEqual(change.differences, ['enabled: expected true, found false']);
    assert.deepEqual(change.requests, [{ method: 'PUT', path: 'immutable-releases' }]);
  });

  it('limits Actions to the allowed list, enabling the list after selecting it', () => {
    const allowed = plan.find((c) => c.setting === 'Actions: allowed actions');
    assert.deepEqual(allowed.differences, ['allowed_actions: expected "selected", found "all"']);
    assert.deepEqual(allowed.requests, [
      {
        method: 'PUT',
        path: 'actions/permissions',
        body: { enabled: true, allowed_actions: 'selected' },
      },
    ]);

    // GitHub answers 409 for the list while all actions are allowed, so there is no list yet.
    const list = plan.find((c) => c.setting === 'Actions: allowed actions list');
    assert.deepEqual(list.differences, ['no list yet (all actions are allowed)']);
    assert.deepEqual(list.requests, [
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
    assert.ok(
      settings.indexOf('Actions: allowed actions') <
        settings.indexOf('Actions: allowed actions list')
    );
  });

  it('requires approval for workflows from all outside contributors', () => {
    const change = plan.find((c) => c.setting === 'Actions: outside contributor approval');
    assert.deepEqual(change.differences, [
      'approval_policy: expected "all_external_contributors", found "first_time_contributors"',
    ]);
    assert.deepEqual(change.requests, [
      {
        method: 'PUT',
        path: 'actions/permissions/fork-pr-contributor-approval',
        body: { approval_policy: 'all_external_contributors' },
      },
    ]);
  });

  it('extends the existing main ruleset in place', () => {
    const change = plan.find((c) => c.setting === 'Ruleset "Protect main from accidents"');
    assert.deepEqual(change.differences, [
      'bypass_actors: expected [{"actor_id":5,"actor_type":"RepositoryRole","bypass_mode":"always"}], found []',
      'rules: missing pull_request',
      'rules: missing required_status_checks',
    ]);
    assert.equal(change.requests.length, 1);
    const [request] = change.requests;
    assert.equal(request.method, 'PUT');
    assert.equal(request.path, 'rulesets/21795519');
    assert.deepEqual(
      request.body.rules.map((rule) => rule.type),
      ['deletion', 'non_fast_forward', 'pull_request', 'required_status_checks']
    );
    assert.deepEqual(
      request.body.rules[3].parameters.required_status_checks.map((check) => check.context),
      ['TypeScript, tests, and web builds', 'PDF browser rendering', 'iOS XCTest', 'Android JUnit']
    );
  });

  it('creates the Release tag ruleset that only the admin role can bypass', () => {
    const change = plan.find((c) => c.setting === 'Ruleset "Release tags"');
    assert.deepEqual(change.differences, ['ruleset does not exist']);
    assert.deepEqual(change.requests, [
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
    const change = plan.find((c) => c.setting === 'Environment "npm-publish"');
    assert.deepEqual(change.differences, ['environment does not exist']);
    assert.deepEqual(change.requests, [
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

  it('adds v* tags to the github-pages deployment policy without touching the rest', () => {
    const change = plan.find((c) => c.setting === 'Environment "github-pages"');
    assert.deepEqual(change.differences, ['deployment policy: missing tag "v*"']);
    assert.deepEqual(change.requests, [
      {
        method: 'POST',
        path: 'environments/github-pages/deployment-branch-policies',
        body: { name: 'v*', type: 'tag' },
      },
    ]);
  });

  it('leaves the already read-only workflow token alone', () => {
    assert.ok(!settingsWithChanges(plan).includes('Actions: workflow token'));
  });
});

describe('planChanges against settings already in the desired state', () => {
  // As GitHub returns them: extra metadata and defaults, lists in its own order.
  const compliant = fixture('after-lockdown');

  it('finds nothing to change, so a second apply sends no requests', () => {
    assert.deepEqual(planChanges(desiredState, compliant), []);
  });
});

describe('planChanges reports drift from the desired state', () => {
  const drifted = (mutate) => {
    const snapshot = fixture('after-lockdown');
    mutate(snapshot);
    return planChanges(desiredState, snapshot);
  };
  const ruleset = (snapshot, name) => snapshot.rulesets.find((r) => r.name === name);

  it('reports an app added as a Release tag bypass actor', () => {
    const plan = drifted((s) =>
      ruleset(s, 'Release tags').bypass_actors.push({
        actor_id: 29110,
        actor_type: 'Integration',
        bypass_mode: 'always',
      })
    );
    assert.deepEqual(settingsWithChanges(plan), ['Ruleset "Release tags"']);
    assert.match(plan[0].differences[0], /^bypass_actors: expected .* found .*Integration/);
  });

  it('reports a required check that was removed from main', () => {
    const plan = drifted((s) => {
      const checks = ruleset(s, 'Protect main from accidents').rules.find(
        (r) => r.type === 'required_status_checks'
      ).parameters.required_status_checks;
      checks.splice(
        checks.findIndex((c) => c.context === 'iOS XCTest'),
        1
      );
    });
    assert.deepEqual(settingsWithChanges(plan), ['Ruleset "Protect main from accidents"']);
    assert.match(
      plan[0].differences[0],
      /^rules\.required_status_checks\.required_status_checks: /
    );
  });

  it('reports a rule that is not in the desired state', () => {
    const plan = drifted((s) =>
      ruleset(s, 'Release tags').rules.push({ type: 'non_fast_forward' })
    );
    assert.deepEqual(plan[0].differences, ['rules: unexpected non_fast_forward']);
  });

  it('reports a required reviewer on npm-publish and puts the environment back', () => {
    const plan = drifted((s) =>
      s.environments['npm-publish'].environment.protection_rules.push({
        id: 1,
        type: 'required_reviewers',
        prevent_self_review: false,
        reviewers: [{ type: 'User', reviewer: { id: 42, login: 'someone' } }],
      })
    );
    assert.deepEqual(plan[0].differences, [
      'reviewers: expected [], found [{"type":"User","id":42}]',
    ]);
    assert.equal(plan[0].requests[0].method, 'PUT');
    assert.equal(plan[0].requests[0].path, 'environments/npm-publish');
  });

  it('deletes an extra deployment policy on npm-publish', () => {
    const plan = drifted((s) =>
      s.environments['npm-publish'].branchPolicies.push({ id: 777, name: 'feat/*', type: 'branch' })
    );
    assert.deepEqual(plan[0].differences, ['deployment policy: unexpected branch "feat/*"']);
    assert.deepEqual(plan[0].requests, [
      { method: 'DELETE', path: 'environments/npm-publish/deployment-branch-policies/777' },
    ]);
  });

  it('ignores the order GitHub returns the allowed actions in', () => {
    assert.deepEqual(
      drifted((s) => s.selectedActions.patterns_allowed.reverse()),
      []
    );
  });

  it('reports a workflow token that can approve pull requests', () => {
    const plan = drifted((s) => (s.workflowPermissions.can_approve_pull_request_reviews = true));
    assert.deepEqual(plan[0].differences, [
      'can_approve_pull_request_reviews: expected false, found true',
    ]);
  });
});
