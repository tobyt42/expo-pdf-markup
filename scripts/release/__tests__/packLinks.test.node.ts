import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { linksMissingFromPack, relativeLinkTargets } from '../packLinks.ts';

describe('relativeLinkTargets', () => {
  it('keeps relative file links and drops anchors, URLs and code', () => {
    const markdown = [
      '[a](docs/a.md) [b](docs/b.md#part) [c](https://example.com/x.md) [d](#top)',
      '[e](mailto:me@example.com) `[f](docs/f.md)`',
      '```',
      '[g](docs/g.md)',
      '```',
    ].join('\n');

    expect(relativeLinkTargets(markdown)).toEqual(['docs/a.md', 'docs/b.md']);
  });
});

describe('linksMissingFromPack', () => {
  it('reports links to files the pack would not include', () => {
    const markdown = '[in](docs/in.md) [out](docs/adr/0001.md)';

    expect(linksMissingFromPack(markdown, 'README.md', ['README.md', 'docs/in.md'])).toEqual([
      'docs/adr/0001.md',
    ]);
  });

  it('resolves links relative to the linking file', () => {
    expect(
      linksMissingFromPack('[up](../README.md) [sibling](b.md)', 'docs/a.md', [
        'README.md',
        'docs/b.md',
      ])
    ).toEqual([]);
  });
});

describe('the published package', () => {
  const [report] = JSON.parse(
    execFileSync('npm', ['pack', '--dry-run', '--json', '--ignore-scripts'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    })
  ) as { files: { path: string }[] }[];
  const packed = report!.files.map((file) => file.path);

  it('ships the consumer docs and keeps the internal ones out', () => {
    expect(packed).toEqual(
      expect.arrayContaining(['docs/annotation-coordinates.md', 'docs/annotation-validation.md'])
    );
    expect(packed.filter((path) => /^(docs\/(adr|agents)\/|GLOSSARY\.md)/.test(path))).toEqual([]);
  });

  it.each(['README.md', 'docs/annotation-coordinates.md', 'docs/annotation-validation.md'])(
    'has every relative link in %s',
    (file) => {
      expect(linksMissingFromPack(readFileSync(file, 'utf8'), file, packed)).toEqual([]);
    }
  );
});
