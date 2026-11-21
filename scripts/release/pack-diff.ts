// Prints the published-package diff for a Release PR body (see .agents/skills/release/SKILL.md):
// the file list and sizes of a fresh dry-run pack of this checkout, compared with a version on
// npm. Rebuilds build/ first, so the pack matches what CI would publish. Publishes nothing.
//
// Usage (from the repository root):
//   node scripts/release/pack-diff.ts               # against the version under `latest`
//   node scripts/release/pack-diff.ts --against 2.0.0
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { diffPackages, type PackReport } from './packDiff.ts';

const root = resolve(import.meta.dirname, '../..');

function run(command: string, args: string[]): string {
  return execFileSync(command, args, {
    cwd: root,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'inherit'],
    maxBuffer: 64 * 1024 * 1024,
  }).trim();
}

function pack(spec?: string): PackReport {
  const args = ['pack', '--dry-run', '--json', '--ignore-scripts'];
  const [report] = JSON.parse(run('npm', spec ? [...args, spec] : args)) as PackReport[];
  if (!report) throw new Error(`npm pack reported nothing for ${spec ?? 'this checkout'}`);
  return report;
}

const { name } = JSON.parse(readFileSync(resolve(root, 'package.json'), 'utf8')) as {
  name: string;
};
const flag = process.argv.indexOf('--against');
const against =
  flag === -1 ? run('npm', ['view', name, 'dist-tags.latest']) : process.argv[flag + 1];
if (!against) throw new Error('--against needs a version');

run('npm', ['run', '--silent', 'clean']);
run('npm', ['run', '--silent', 'build']);
process.stdout.write(diffPackages(pack(`${name}@${against}`), pack()));
