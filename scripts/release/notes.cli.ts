// Prints the Release notes for the package.json version: the body of its `## <version>`
// section in CHANGELOG.md, exactly as the Release checks in releasePlan.ts take them for the
// GitHub Release. Used for the Release PR body (see .agents/skills/release/SKILL.md). Exits 1
// when there is no such section.
//
// Usage (from the repository root): node scripts/release/notes.cli.ts
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { readPackageJson, root } from '../lib/repo.ts';
import { releaseNotes } from './releasePlan.ts';

const { version } = readPackageJson();
const notes = releaseNotes(readFileSync(resolve(root, 'CHANGELOG.md'), 'utf8'), version);
if (notes === null) {
  console.error(`CHANGELOG.md has no "## ${version}" section with release notes`);
  process.exitCode = 1;
} else {
  console.log(notes);
}
