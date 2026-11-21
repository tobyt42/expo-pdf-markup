// Puts the repository settings into the desired state in desiredState.ts (rulesets, immutable
// releases, Actions permissions, deployment environments). Node runs this file directly.
//
//   node scripts/repo-settings/settings.cli.ts --check     read-only; lists every difference,
//                                                          exits 1 on drift
//   node scripts/repo-settings/settings.cli.ts apply       sends only the changes --check
//                                                          reports, then checks again
//   node scripts/repo-settings/settings.cli.ts --snapshot  read-only; prints the live settings
//                                                          as fixture JSON
//
// Needs `gh` authenticated as a repository admin. Runs against the repository `gh` resolves from
// the current directory, or the one passed with --repo owner/name.
import { desiredState } from './desiredState.ts';
import { currentRepository, readSnapshot, send } from './github.ts';
import { planChanges, type SettingChange } from './settingsPlan.ts';

const usage =
  'Usage: node scripts/repo-settings/settings.cli.ts (--check | apply | --snapshot) [--repo owner/name]';

const args = process.argv.slice(2);
const repoIndex = args.indexOf('--repo');
const repository = repoIndex === -1 ? currentRepository() : args[repoIndex + 1];
const modes = repoIndex === -1 ? args : args.toSpliced(repoIndex, 2);

const [mode] = modes;
if (modes.length !== 1 || !['--check', 'apply', '--snapshot'].includes(mode ?? '') || !repository) {
  console.error(usage);
  process.exit(2);
}

if (mode === '--snapshot') {
  console.log(JSON.stringify(readSnapshot(repository), null, 2));
  process.exit(0);
}

const plan = planChanges(desiredState, readSnapshot(repository));
report(plan);

if (mode === '--check') {
  process.exit(plan.length === 0 ? 0 : 1);
}

for (const change of plan) {
  for (const request of change.requests) {
    console.log(`${request.method} ${request.path}`);
    send(repository, request);
  }
}
if (plan.length > 0) {
  console.log('\nChecking again after apply:');
  const remaining = planChanges(desiredState, readSnapshot(repository));
  report(remaining);
  process.exit(remaining.length === 0 ? 0 : 1);
}

function report(changes: SettingChange[]): void {
  if (changes.length === 0) {
    console.log(`${repository}: settings match the desired state.`);
    return;
  }
  console.log(`${repository}: ${changes.length} setting(s) differ from the desired state.\n`);
  for (const change of changes) {
    console.log(change.setting);
    for (const difference of change.differences) console.log(`  - ${difference}`);
  }
  console.log('');
}
