// Prints the published-package diff for a Release PR body (see .agents/skills/release/SKILL.md):
// the file list and sizes of a fresh dry-run pack of this checkout, compared with the version
// under npm's `latest` dist-tag. Rebuilds build/ first, so the pack matches what CI would
// publish. Publishes nothing.
//
// Usage (from the repository root): node scripts/release/pack-diff.cli.ts
import { readPackageJson, run } from '../lib/repo.ts';
import { diffPackages, type PackReport } from './packDiff.ts';

function pack(spec?: string): PackReport {
  const args = ['pack', '--dry-run', '--json', '--ignore-scripts'];
  const output = run('npm', spec ? [...args, spec] : args, { stderr: 'inherit' });
  const [report] = JSON.parse(output) as PackReport[];
  if (!report) throw new Error(`npm pack reported nothing for ${spec ?? 'this checkout'}`);
  return report;
}

const { name } = readPackageJson();
const latest = run('npm', ['view', name, 'dist-tags.latest'], { stderr: 'inherit' });

run('npm', ['run', '--silent', 'clean'], { stderr: 'inherit' });
run('npm', ['run', '--silent', 'build'], { stderr: 'inherit' });
process.stdout.write(diffPackages(pack(`${name}@${latest}`), pack()));
