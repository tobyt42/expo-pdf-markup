// The desired repository settings, as data. `scripts/repo-settings.mjs` compares the live
// settings with this (`--check`) or makes them match (`apply`). See CLAUDE.md "Repository
// settings" and spec #143.
//
// Only the fields listed here are managed: fields GitHub returns that are not listed are
// ignored, and lists (rules, required checks, bypass actors, patterns, deployment policies)
// must match exactly.

// The Repository admin role. It is the only actor allowed to bypass either ruleset, so only the
// maintainer can create, move or delete Release tags or push to `main` without a pull request.
const adminBypass = [{ actor_id: 5, actor_type: 'RepositoryRole', bypass_mode: 'always' }];

// GitHub Actions app: the required checks must come from Actions, not any other status source.
const githubActions = 15368;

// Job names of the pull request validation runs (validate-*.yml). When the same workflows run
// from release.yml their contexts are prefixed ("Web / ..."), and those are not the required ones.
const requiredChecks = [
  'TypeScript, tests, and web builds',
  'PDF browser rendering',
  'iOS XCTest',
  'Android JUnit',
];

export const desiredState = {
  rulesets: [
    {
      // The existing `main` ruleset, extended; it is found by this name.
      name: 'Protect main from accidents',
      target: 'branch',
      enforcement: 'active',
      conditions: { ref_name: { include: ['~DEFAULT_BRANCH'], exclude: [] } },
      bypass_actors: adminBypass,
      rules: [
        { type: 'deletion' },
        { type: 'non_fast_forward' },
        {
          type: 'pull_request',
          parameters: {
            required_approving_review_count: 0,
            dismiss_stale_reviews_on_push: false,
            require_code_owner_review: false,
            require_last_push_approval: false,
            required_review_thread_resolution: false,
            allowed_merge_methods: ['merge', 'squash', 'rebase'],
          },
        },
        {
          type: 'required_status_checks',
          parameters: {
            strict_required_status_checks_policy: false,
            do_not_enforce_on_create: false,
            required_status_checks: requiredChecks.map((context) => ({
              context,
              integration_id: githubActions,
            })),
          },
        },
      ],
    },
    {
      name: 'Release tags',
      target: 'tag',
      enforcement: 'active',
      conditions: { ref_name: { include: ['refs/tags/v*'], exclude: [] } },
      bypass_actors: adminBypass,
      rules: [{ type: 'creation' }, { type: 'update' }, { type: 'deletion' }],
    },
  ],

  immutableReleases: { enabled: true },

  actions: {
    permissions: { enabled: true, allowed_actions: 'selected' },
    // GitHub's own actions (actions/*, github/*) plus the third-party actions the workflows use.
    // Local reusable workflows (./.github/workflows/...) are always allowed.
    selectedActions: {
      github_owned_allowed: true,
      verified_allowed: false,
      patterns_allowed: [
        'android-actions/setup-android@*',
        'gradle/actions/setup-gradle@*',
        'ruby/setup-ruby@*',
      ],
    },
    workflow: { default_workflow_permissions: 'read', can_approve_pull_request_reviews: false },
    forkPrApproval: { approval_policy: 'all_external_contributors' },
  },

  environments: [
    {
      // The npm trusted publisher is bound to this environment (ADR 0002). No required reviewer:
      // merging the Release PR is the approval. Admins cannot bypass the deployment policy.
      name: 'npm-publish',
      settings: { can_admins_bypass: false, reviewers: [], wait_timer: 0 },
      deploymentPolicies: [
        { name: 'main', type: 'branch' },
        { name: 'v*', type: 'tag' },
      ],
    },
    {
      // Docs deploy only from Releases: release.yml calls docs.yml after a Release tag (v*)
      // publishes. docs.yml has no other trigger, so no branch may deploy.
      name: 'github-pages',
      settings: {},
      deploymentPolicies: [{ name: 'v*', type: 'tag' }],
    },
  ],
};
