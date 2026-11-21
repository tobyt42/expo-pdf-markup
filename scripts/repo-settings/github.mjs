// The only part of the settings script that talks to GitHub, through the `gh` CLI.
import { execFileSync } from 'node:child_process';

function gh(args, input) {
  return execFileSync('gh', args, {
    encoding: 'utf8',
    input,
    stdio: ['pipe', 'pipe', 'inherit'],
  });
}

export function currentRepository() {
  return gh(['repo', 'view', '--json', 'nameWithOwner', '--jq', '.nameWithOwner']).trim();
}

// Reads every setting the plan compares, with GET requests only.
export function readSnapshot(repository) {
  const get = (path) => JSON.parse(gh(['api', `repos/${repository}/${path}`]));

  const actionsPermissions = get('actions/permissions');
  const environments = {};
  for (const environment of get('environments').environments) {
    environments[environment.name] = {
      environment,
      branchPolicies: environment.deployment_branch_policy?.custom_branch_policies
        ? get(`environments/${encodeURIComponent(environment.name)}/deployment-branch-policies`)
            .branch_policies
        : [],
    };
  }

  return {
    rulesets: get('rulesets').map((ruleset) => get(`rulesets/${ruleset.id}`)),
    actionsPermissions,
    // GitHub answers 409 Conflict for the list unless allowed actions is `selected`.
    selectedActions:
      actionsPermissions.allowed_actions === 'selected'
        ? get('actions/permissions/selected-actions')
        : null,
    workflowPermissions: get('actions/permissions/workflow'),
    forkPrApproval: get('actions/permissions/fork-pr-contributor-approval'),
    immutableReleases: get('immutable-releases'),
    environments,
  };
}

export function send(repository, request) {
  const args = ['api', '--method', request.method, `repos/${repository}/${request.path}`];
  if (request.body === undefined) {
    gh(args);
  } else {
    gh([...args, '--input', '-'], JSON.stringify(request.body));
  }
}
