// CI wrapper around the release plan module: collects the real facts, asks planRelease what
// to do and reports the answer. It holds no decisions of its own.
//
// Run by the `plan` job in .github/workflows/release.yml (Node runs this file directly with
// type stripping). Writes `action`, `publish` and, when publishing, `version`, `dist-tag` and
// (for a Release) `notes` to $GITHUB_OUTPUT for the later jobs, prints the plan and exits
// non-zero on a refusal.
//
// Local dry run (read-only; needs a fetched `origin/main`):
//   GITHUB_REF=refs/heads/main node scripts/release/plan.cli.ts
//   GITHUB_REF=refs/tags/v2.0.0 node scripts/release/plan.cli.ts
import { readChangesets } from '@changesets/read';
import { randomUUID } from 'node:crypto';
import { appendFileSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { readPackageJson, root, run } from '../lib/repo.ts';
import {
  planOutputs,
  planRelease,
  type BumpType,
  type PendingChangeset,
  type ReleaseFacts,
  type ReleasePlan,
} from './releasePlan.ts';

function commitOnMain(): boolean {
  try {
    run('git', ['merge-base', '--is-ancestor', 'HEAD', 'refs/remotes/origin/main']);
    return true;
  } catch (error) {
    // Exit status 1 means "not an ancestor"; anything else (e.g. no origin/main) is an error.
    if ((error as { status?: number }).status === 1) return false;
    throw error;
  }
}

function versionPublished(name: string, version: string): boolean {
  try {
    return run('npm', ['view', `${name}@${version}`, 'version', '--json']) !== '';
  } catch (error) {
    // npm exits non-zero with E404 when the package itself has never been published.
    if (String((error as { stderr?: unknown }).stderr).includes('E404')) return false;
    throw error;
  }
}

async function pendingChangesets(name: string): Promise<PendingChangeset[]> {
  const changesets = await readChangesets(root);
  return changesets.map(({ id, releases }) => ({
    id,
    bump: (releases.find((release) => release.name === name)?.type ?? 'none') as BumpType,
  }));
}

async function collectFacts(): Promise<ReleaseFacts> {
  const ref = process.env.GITHUB_REF;
  if (!ref) throw new Error('GITHUB_REF is not set');
  const pkg = readPackageJson();
  return {
    ref,
    packageVersion: pkg.version,
    pendingChangesets: await pendingChangesets(pkg.name),
    commitOnMain: commitOnMain(),
    versionPublished: versionPublished(pkg.name, pkg.version),
    changelog: readFileSync(resolve(root, 'CHANGELOG.md'), 'utf8'),
    now: new Date(),
  };
}

function report(facts: ReleaseFacts, plan: ReleasePlan): void {
  const { changelog: _changelog, ...shown } = facts;
  console.log('Facts:', JSON.stringify(shown, null, 2));
  console.log('Plan:', JSON.stringify(plan, null, 2));

  const outputs = planOutputs(plan);
  if (process.env.GITHUB_OUTPUT) {
    // Multiline values use GitHub's heredoc form, with a delimiter no changelog can contain.
    const delimiter = `EOF_${randomUUID()}`;
    const lines = Object.entries(outputs).map(([key, value]) =>
      value.includes('\n') ? `${key}<<${delimiter}\n${value}\n${delimiter}\n` : `${key}=${value}\n`
    );
    appendFileSync(process.env.GITHUB_OUTPUT, lines.join(''));
  }
  if (process.env.GITHUB_STEP_SUMMARY) {
    const detail =
      plan.action === 'skip' || plan.action === 'refuse'
        ? plan.reason
        : `${plan.version} under the \`${plan.distTag}\` dist-tag`;
    const notes = plan.action === 'release' ? `\n#### Release notes\n\n${plan.notes}\n` : '';
    appendFileSync(
      process.env.GITHUB_STEP_SUMMARY,
      `### Release plan: ${plan.action}\n\n${detail}\n${notes}`
    );
  }
}

const facts = await collectFacts();
const plan = planRelease(facts);
report(facts, plan);
if (plan.action === 'refuse') {
  console.error(`Refused: ${plan.reason}`);
  process.exitCode = 1;
}
