import { diffPackages, type PackReport } from '../packDiff.ts';

function report(version: string, files: [string, number][], size = 1000): PackReport {
  return {
    version,
    size,
    unpackedSize: files.reduce((total, [, fileSize]) => total + fileSize, 0),
    files: files.map(([path, fileSize]) => ({ path, size: fileSize })),
  };
}

describe('diffPackages', () => {
  it('summarises file count and sizes for both versions', () => {
    const markdown = diffPackages(
      report('2.0.0', [['build/index.js', 2048]], 1024),
      report('2.0.1', [['build/index.js', 2048]], 1536)
    );

    expect(markdown).toContain('### Published package: 2.0.0 → 2.0.1');
    expect(markdown).toContain('| Files | 1 | 1 | 0 |');
    expect(markdown).toContain('| Packed size | 1.0 kB | 1.5 kB | +512 B |');
    expect(markdown).toContain('| Unpacked size | 2.0 kB | 2.0 kB | 0 |');
  });

  it('lists added, removed and resized files, and counts the unchanged ones', () => {
    const markdown = diffPackages(
      report('2.0.0', [
        ['README.md', 100],
        ['build/old.js', 300],
        ['build/index.js', 500],
      ]),
      report('2.1.0', [
        ['README.md', 100],
        ['build/new.js', 200],
        ['build/index.js', 400],
      ])
    );

    expect(markdown).toContain(
      '**Added (1)**\n\n| File | Size |\n| --- | --- |\n| `build/new.js` | 200 B |'
    );
    expect(markdown).toContain(
      '**Removed (1)**\n\n| File | Size |\n| --- | --- |\n| `build/old.js` | 300 B |'
    );
    expect(markdown).toContain(
      '**Size changed (1)**\n\n| File | 2.0.0 | 2.1.0 | Change |\n| --- | --- | --- | --- |\n| `build/index.js` | 500 B | 400 B | −100 B |'
    );
    expect(markdown).toContain('1 file unchanged in size.');
  });

  it('signs a change in the file count', () => {
    const markdown = diffPackages(
      report('2.0.0', [['a.js', 1]]),
      report('2.0.1', [
        ['a.js', 1],
        ['b.js', 2],
      ])
    );

    expect(markdown).toContain('| Files | 1 | 2 | +1 |');
  });

  it('omits empty sections when nothing changed', () => {
    const files: [string, number][] = [
      ['a.js', 1],
      ['b.js', 2],
    ];
    const markdown = diffPackages(report('2.0.0', files), report('2.0.1', files));

    expect(markdown).not.toContain('**Added');
    expect(markdown).not.toContain('**Removed');
    expect(markdown).not.toContain('**Size changed');
    expect(markdown).toContain('2 files unchanged in size.');
  });
});
