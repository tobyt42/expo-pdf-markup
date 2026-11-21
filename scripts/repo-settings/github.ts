// The only part of the settings script that talks to GitHub, through the `gh` CLI.
import { run } from '../lib/repo.ts';
import type { LiveEnvironment, LiveRuleset, SettingsRequest, Snapshot } from './settingsPlan.ts';

function gh(args: string[], input?: string): string {
  return run('gh', args, { input, stderr: 'inherit' });
}

export function currentRepository(): string {
  return gh(['repo', 'view', '--json', 'nameWithOwner', '--jq', '.nameWithOwner']);
}

// Reads every setting the plan compares, with GET requests only.
export function readSnapshot(repository: string): Snapshot {
  const get = <T>(path: string): T => JSON.parse(gh(['api', `repos/${repository}/${path}`])) as T;

  const actionsPermissions = get<Snapshot['actionsPermissions']>('actions/permissions');
  const environments: Snapshot['environments'] = {};
  for (const environment of get<{ environments: LiveEnvironment['environment'][] }>('environments')
    .environments) {
    environments[environment.name] = {
      environment,
      branchPolicies: environment.deployment_branch_policy?.custom_branch_policies
        ? get<{ branch_policies: LiveEnvironment['branchPolicies'] }>(
            `environments/${encodeURIComponent(environment.name)}/deployment-branch-policies`
          ).branch_policies
        : [],
    };
  }

  return {
    rulesets: get<{ id: number }[]>('rulesets').map((ruleset) =>
      get<LiveRuleset>(`rulesets/${ruleset.id}`)
    ),
    actionsPermissions,
    // GitHub answers 409 Conflict for the list unless allowed actions is `selected`.
    selectedActions:
      actionsPermissions.allowed_actions === 'selected'
        ? get<Snapshot['selectedActions']>('actions/permissions/selected-actions')
        : null,
    workflowPermissions: get('actions/permissions/workflow'),
    forkPrApproval: get('actions/permissions/fork-pr-contributor-approval'),
    immutableReleases: get('immutable-releases'),
    environments,
  };
}

export function send(repository: string, request: SettingsRequest): void {
  const args = ['api', '--method', request.method, `repos/${repository}/${request.path}`];
  if (request.body === undefined) {
    gh(args);
  } else {
    gh([...args, '--input', '-'], JSON.stringify(request.body));
  }
}
