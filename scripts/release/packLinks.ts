// Checks that the relative links in a Markdown file point at files the published package
// contains. Pure: callers pass the Markdown and the packed file paths.
import { posix } from 'node:path';

/** Relative file targets of the inline Markdown links in `markdown`, without `#anchors`. */
export function relativeLinkTargets(markdown: string): string[] {
  const withoutCode = markdown.replace(/```[\s\S]*?```/g, '').replace(/`[^`\n]*`/g, '');
  const targets: string[] = [];
  for (const match of withoutCode.matchAll(/\[[^\]]*\]\(\s*<?([^)\s>]+)/g)) {
    const target = match[1]!;
    if (/^([a-z][a-z0-9+.-]*:|\/\/|#)/i.test(target)) continue;
    const file = target.split('#')[0]!.split('?')[0]!;
    if (file) targets.push(file);
  }
  return targets;
}

/** Link targets in `markdown` (a file at `fromPath`) that are not among `packedPaths`. */
export function linksMissingFromPack(
  markdown: string,
  fromPath: string,
  packedPaths: readonly string[]
): string[] {
  const packed = new Set(packedPaths);
  return relativeLinkTargets(markdown)
    .map((target) => posix.normalize(posix.join(posix.dirname(fromPath), target)))
    .filter((resolved) => !packed.has(resolved));
}
