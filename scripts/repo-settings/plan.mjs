// Pure comparison of the desired repository settings with a snapshot of the live ones. No
// network: `github.mjs` reads the snapshot and sends the requests.

export function planChanges(desired, snapshot) {
  const plan = [];
  const add = (setting, differences, requests) => {
    if (differences.length > 0) plan.push({ setting, differences, requests });
  };

  for (const ruleset of desired.rulesets) {
    const live = snapshot.rulesets.find((candidate) => candidate.name === ruleset.name);
    const setting = `Ruleset "${ruleset.name}"`;
    if (!live) {
      add(
        setting,
        ['ruleset does not exist'],
        [{ method: 'POST', path: 'rulesets', body: ruleset }]
      );
      continue;
    }
    add(setting, compareRuleset(ruleset, live), [
      { method: 'PUT', path: `rulesets/${live.id}`, body: ruleset },
    ]);
  }

  add(
    'Immutable releases',
    compare(desired.immutableReleases, snapshot.immutableReleases),
    desired.immutableReleases.enabled
      ? [{ method: 'PUT', path: 'immutable-releases' }]
      : [{ method: 'DELETE', path: 'immutable-releases' }]
  );

  // Order matters: the allowed actions list can only be written once `selected` is set.
  const actionSettings = [
    ['Actions: allowed actions', 'permissions', 'actionsPermissions', 'actions/permissions'],
    [
      'Actions: allowed actions list',
      'selectedActions',
      'selectedActions',
      'actions/permissions/selected-actions',
    ],
    ['Actions: workflow token', 'workflow', 'workflowPermissions', 'actions/permissions/workflow'],
    [
      'Actions: outside contributor approval',
      'forkPrApproval',
      'forkPrApproval',
      'actions/permissions/fork-pr-contributor-approval',
    ],
  ];
  for (const [setting, desiredKey, snapshotKey, path] of actionSettings) {
    const body = desired.actions[desiredKey];
    const live = snapshot[snapshotKey];
    const differences = live ? compare(body, live) : ['no list yet (all actions are allowed)'];
    add(setting, differences, [{ method: 'PUT', path, body }]);
  }

  for (const environment of desired.environments) {
    const live = snapshot.environments[environment.name];
    const [differences, requests] = planEnvironment(environment, live);
    add(`Environment "${environment.name}"`, differences, requests);
  }

  return plan;
}

const customPolicies = { protected_branches: false, custom_branch_policies: true };

function planEnvironment(desired, live) {
  const policiesPath = `environments/${desired.name}/deployment-branch-policies`;
  const differences = [];
  const requests = [];

  const settingsDifferences = live
    ? [
        ...compare(desired.settings, environmentSettings(live.environment)),
        ...compare(customPolicies, live.environment.deployment_branch_policy, 'deployment policy'),
      ]
    : ['environment does not exist'];
  if (settingsDifferences.length > 0) {
    differences.push(...settingsDifferences);
    requests.push({
      method: 'PUT',
      path: `environments/${desired.name}`,
      body: { ...desired.settings, deployment_branch_policy: customPolicies },
    });
  }

  const livePolicies = live?.branchPolicies ?? [];
  const samePolicy = (a, b) => a.name === b.name && a.type === b.type;
  for (const policy of desired.deploymentPolicies) {
    if (!livePolicies.some((candidate) => samePolicy(candidate, policy))) {
      if (live) differences.push(`deployment policy: missing ${policy.type} "${policy.name}"`);
      requests.push({ method: 'POST', path: policiesPath, body: policy });
    }
  }
  for (const policy of livePolicies) {
    if (!desired.deploymentPolicies.some((candidate) => samePolicy(candidate, policy))) {
      differences.push(`deployment policy: unexpected ${policy.type} "${policy.name}"`);
      requests.push({ method: 'DELETE', path: `${policiesPath}/${policy.id}` });
    }
  }
  return [differences, requests];
}

// The environment as GitHub returns it, in the shape its PUT request takes.
function environmentSettings(environment) {
  const rule = (type) => environment.protection_rules.find((candidate) => candidate.type === type);
  return {
    can_admins_bypass: environment.can_admins_bypass,
    wait_timer: rule('wait_timer')?.wait_timer ?? 0,
    reviewers: (rule('required_reviewers')?.reviewers ?? []).map((reviewer) => ({
      type: reviewer.type,
      id: reviewer.reviewer.id,
    })),
  };
}

// Rules are matched by type, since GitHub adds default parameters we do not manage.
function compareRuleset(expected, actual) {
  const { rules, ...rest } = expected;
  const differences = compare(rest, actual);
  for (const rule of rules) {
    const live = actual.rules.find((candidate) => candidate.type === rule.type);
    if (!live) {
      differences.push(`rules: missing ${rule.type}`);
    } else if (rule.parameters) {
      differences.push(...compare(rule.parameters, live.parameters, `rules.${rule.type}`));
    }
  }
  for (const live of actual.rules) {
    if (!rules.some((rule) => rule.type === live.type)) {
      differences.push(`rules: unexpected ${live.type}`);
    }
  }
  return differences;
}

function sortLists(value) {
  if (Array.isArray(value)) {
    return value.map(sortLists).sort((a, b) => show(a).localeCompare(show(b)));
  }
  if (!isObject(value)) return value;
  return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, sortLists(item)]));
}

// Lists how `actual` differs from `expected`. Objects are compared on the keys of `expected`
// only; arrays must hold the same items in any order (GitHub picks its own), scalars must match.
function compare(expected, actual, path = '') {
  const label = (key) => (path ? `${path}.${key}` : key);
  if (isObject(expected) && !Array.isArray(expected)) {
    if (!isObject(actual) || Array.isArray(actual)) {
      return [`${path || 'value'}: expected ${show(expected)}, found ${show(actual)}`];
    }
    return Object.keys(expected).flatMap((key) => compare(expected[key], actual[key], label(key)));
  }
  if (show(sortLists(expected)) === show(sortLists(actual))) return [];
  return [`${path || 'value'}: expected ${show(expected)}, found ${show(actual)}`];
}

const isObject = (value) => typeof value === 'object' && value !== null;
const show = (value) => (value === undefined ? 'nothing' : JSON.stringify(value));
