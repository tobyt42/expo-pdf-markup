// Pure comparison of the desired repository settings with a snapshot of the live ones. No
// network: `github.ts` reads the snapshot and sends the requests.

/** A request `apply` sends to `repos/<owner>/<name>/<path>` through `gh api`. */
export interface SettingsRequest {
  method: 'POST' | 'PUT' | 'DELETE';
  path: string;
  body?: unknown;
}

/** One setting that differs from the desired state, and the requests that put it back. */
export interface SettingChange {
  setting: string;
  differences: string[];
  requests: SettingsRequest[];
}

export interface Rule {
  type: string;
  parameters?: Record<string, unknown>;
}

export interface Ruleset {
  name: string;
  target: 'branch' | 'tag';
  enforcement: 'active' | 'evaluate' | 'disabled';
  conditions: { ref_name: { include: string[]; exclude: string[] } };
  bypass_actors: { actor_id: number; actor_type: string; bypass_mode: string }[];
  rules: Rule[];
}

/** A ruleset as GitHub returns it: the managed fields plus its id and metadata. */
export interface LiveRuleset extends Ruleset {
  id: number;
  [field: string]: unknown;
}

export interface DeploymentPolicy {
  name: string;
  type: 'branch' | 'tag';
}

/** The environment fields its PUT request takes; only the ones given are managed. */
export interface EnvironmentSettings {
  can_admins_bypass?: boolean;
  wait_timer?: number;
  reviewers?: { type: string; id: number }[];
}

export interface DesiredEnvironment {
  name: string;
  settings: EnvironmentSettings;
  deploymentPolicies: DeploymentPolicy[];
}

/** The environment and its deployment policies, as GitHub returns them. */
export interface LiveEnvironment {
  environment: {
    name: string;
    can_admins_bypass: boolean;
    protection_rules: {
      type: string;
      wait_timer?: number;
      [field: string]: unknown;
      reviewers?: { type: string; reviewer: { id: number; [field: string]: unknown } }[];
    }[];
    deployment_branch_policy: {
      protected_branches: boolean;
      custom_branch_policies: boolean;
    } | null;
  };
  branchPolicies: (DeploymentPolicy & { id: number })[];
}

/** The Actions settings, each read and written whole at its own API path. */
export interface ActionsSettings {
  actionsPermissions: { enabled: boolean; allowed_actions: string };
  selectedActions: {
    github_owned_allowed: boolean;
    verified_allowed: boolean;
    patterns_allowed: string[];
  };
  workflowPermissions: {
    default_workflow_permissions: 'read' | 'write';
    can_approve_pull_request_reviews: boolean;
  };
  forkPrApproval: { approval_policy: string };
}

/** The managed settings. Actions settings use the same keys as the Snapshot. */
export interface DesiredState extends ActionsSettings {
  rulesets: Ruleset[];
  immutableReleases: { enabled: boolean };
  environments: DesiredEnvironment[];
}

/** The live settings, as `github.ts` reads them (and `--snapshot` prints them). */
export interface Snapshot {
  rulesets: LiveRuleset[];
  immutableReleases: { enabled: boolean; [field: string]: unknown };
  actionsPermissions: ActionsSettings['actionsPermissions'];
  /** Null while all actions are allowed: GitHub has no list to return then. */
  selectedActions: ActionsSettings['selectedActions'] | null;
  workflowPermissions: ActionsSettings['workflowPermissions'];
  forkPrApproval: ActionsSettings['forkPrApproval'];
  environments: Record<string, LiveEnvironment>;
}

/** The Actions settings in the order they must be written: the allowed actions list can only be
 * written once `selected` is set. */
const actionsSettings: { setting: string; key: keyof ActionsSettings; path: string }[] = [
  { setting: 'Actions: allowed actions', key: 'actionsPermissions', path: 'actions/permissions' },
  {
    setting: 'Actions: allowed actions list',
    key: 'selectedActions',
    path: 'actions/permissions/selected-actions',
  },
  {
    setting: 'Actions: workflow token',
    key: 'workflowPermissions',
    path: 'actions/permissions/workflow',
  },
  {
    setting: 'Actions: outside contributor approval',
    key: 'forkPrApproval',
    path: 'actions/permissions/fork-pr-contributor-approval',
  },
];

export function planChanges(desired: DesiredState, snapshot: Snapshot): SettingChange[] {
  const plan: SettingChange[] = [];
  const add = (setting: string, differences: string[], requests: SettingsRequest[]) => {
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

  for (const { setting, key, path } of actionsSettings) {
    const body = desired[key];
    const live = snapshot[key];
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

function planEnvironment(
  desired: DesiredEnvironment,
  live: LiveEnvironment | undefined
): [string[], SettingsRequest[]] {
  const policiesPath = `environments/${desired.name}/deployment-branch-policies`;
  const differences: string[] = [];
  const requests: SettingsRequest[] = [];

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
  const samePolicy = (a: DeploymentPolicy, b: DeploymentPolicy) =>
    a.name === b.name && a.type === b.type;
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
function environmentSettings(environment: LiveEnvironment['environment']): EnvironmentSettings {
  const rule = (type: string) =>
    environment.protection_rules.find((candidate) => candidate.type === type);
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
function compareRuleset(expected: Ruleset, actual: LiveRuleset): string[] {
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

function sortLists(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value.map(sortLists).sort((a, b) => show(a).localeCompare(show(b)));
  }
  if (!isObject(value)) return value;
  return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, sortLists(item)]));
}

// Lists how `actual` differs from `expected`. Objects are compared on the keys of `expected`
// only; arrays must hold the same items in any order (GitHub picks its own), scalars must match.
function compare(expected: unknown, actual: unknown, path = ''): string[] {
  const label = (key: string) => (path ? `${path}.${key}` : key);
  if (isObject(expected) && !Array.isArray(expected)) {
    if (!isObject(actual) || Array.isArray(actual)) {
      return [`${path || 'value'}: expected ${show(expected)}, found ${show(actual)}`];
    }
    const actualFields = actual as Record<string, unknown>;
    return Object.entries(expected).flatMap(([key, value]) =>
      compare(value, actualFields[key], label(key))
    );
  }
  if (show(sortLists(expected)) === show(sortLists(actual))) return [];
  return [`${path || 'value'}: expected ${show(expected)}, found ${show(actual)}`];
}

const isObject = (value: unknown): value is object => typeof value === 'object' && value !== null;
const show = (value: unknown): string => (value === undefined ? 'nothing' : JSON.stringify(value));
