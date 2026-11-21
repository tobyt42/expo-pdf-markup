// The published-package diff for a Release PR: compares what `npm pack --dry-run --json`
// reports for the new version with the same report for the version on npm, as Markdown.
// Pure: the wrapper (pack-diff.ts) runs npm and passes the parsed reports in.

/** One file in a pack report. */
export interface PackFile {
  path: string;
  size: number;
}

/** The fields of one `npm pack --dry-run --json` entry that the diff uses. */
export interface PackReport {
  version: string;
  size: number;
  unpackedSize: number;
  files: PackFile[];
}

function bytes(size: number): string {
  if (size < 1024) return `${size} B`;
  return `${(size / 1024).toFixed(1)} kB`;
}

function signed(change: number, format: (size: number) => string = String): string {
  if (change === 0) return '0';
  return `${change > 0 ? '+' : '−'}${format(Math.abs(change))}`;
}

function delta(before: number, after: number): string {
  return signed(after - before, bytes);
}

function table(header: string[], rows: string[][]): string {
  const line = (cells: string[]) => `| ${cells.join(' | ')} |`;
  return [line(header), line(header.map(() => '---')), ...rows.map(line)].join('\n');
}

function section(title: string, header: string[], rows: string[][]): string[] {
  if (rows.length === 0) return [];
  return [`**${title} (${rows.length})**`, '', table(header, rows), ''];
}

/** Renders the published-package diff between the version on npm and the new one. */
export function diffPackages(previous: PackReport, next: PackReport): string {
  const before = new Map(previous.files.map((file) => [file.path, file.size]));
  const after = new Map(next.files.map((file) => [file.path, file.size]));
  const paths = [...new Set([...before.keys(), ...after.keys()])].sort();

  const added: string[][] = [];
  const removed: string[][] = [];
  const resized: string[][] = [];
  let unchanged = 0;
  for (const path of paths) {
    const old = before.get(path);
    const current = after.get(path);
    if (old === undefined) added.push([`\`${path}\``, bytes(current!)]);
    else if (current === undefined) removed.push([`\`${path}\``, bytes(old)]);
    else if (old !== current)
      resized.push([`\`${path}\``, bytes(old), bytes(current), delta(old, current)]);
    else unchanged++;
  }

  const { version: from } = previous;
  const { version: to } = next;
  const lines = [
    `### Published package: ${from} → ${to}`,
    '',
    table(
      ['', from, to, 'Change'],
      [
        [
          'Files',
          `${previous.files.length}`,
          `${next.files.length}`,
          signed(next.files.length - previous.files.length),
        ],
        ['Packed size', bytes(previous.size), bytes(next.size), delta(previous.size, next.size)],
        [
          'Unpacked size',
          bytes(previous.unpackedSize),
          bytes(next.unpackedSize),
          delta(previous.unpackedSize, next.unpackedSize),
        ],
      ]
    ),
    '',
    ...section('Added', ['File', 'Size'], added),
    ...section('Removed', ['File', 'Size'], removed),
    ...section('Size changed', ['File', from, to, 'Change'], resized),
    `${unchanged} ${unchanged === 1 ? 'file' : 'files'} unchanged in size.`,
  ];
  return `${lines.join('\n')}\n`;
}
