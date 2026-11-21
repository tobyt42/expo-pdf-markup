// Helpers shared by the Node scripts in scripts/release/ and scripts/repo-settings/: the
// repository root, running a command there, and reading package.json.
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

/** The repository root, whichever directory the script is started from. */
export const root = resolve(import.meta.dirname, '../..');

export interface RunOptions {
  /** Text written to the command's standard input. */
  input?: string;
  /** `inherit` shows the command's errors as they happen; `pipe` keeps them on the thrown error. */
  stderr?: 'pipe' | 'inherit';
}

/** Runs a command in the repository root and returns its trimmed output; throws on failure. */
export function run(command: string, args: string[], options: RunOptions = {}): string {
  return execFileSync(command, args, {
    cwd: root,
    encoding: 'utf8',
    input: options.input,
    stdio: ['pipe', 'pipe', options.stderr ?? 'pipe'],
    maxBuffer: 64 * 1024 * 1024,
  }).trim();
}

export interface PackageJson {
  name: string;
  version: string;
}

export function readPackageJson(): PackageJson {
  return JSON.parse(readFileSync(resolve(root, 'package.json'), 'utf8')) as PackageJson;
}
