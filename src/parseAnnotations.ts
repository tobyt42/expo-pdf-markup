import type { Annotation, AnnotationPoint, AnnotationsData } from './ExpoPdfMarkup.types';

// Platform-neutral: this module is exported from the package entry point on every
// platform, so it must not import anything web-only (e.g. pdfjs).

function isFiniteNumber(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value);
}

/** Reads one ink point in object form or array form; returns null if it is malformed. */
function readInkPoint(raw: unknown): AnnotationPoint | null {
  if (Array.isArray(raw)) {
    if (raw.length !== 2 || !isFiniteNumber(raw[0]) || !isFiniteNumber(raw[1])) return null;
    return { x: raw[0], y: raw[1] };
  }
  if (raw !== null && typeof raw === 'object') {
    const { x, y } = raw as { x?: unknown; y?: unknown };
    if (!isFiniteNumber(x) || !isFiniteNumber(y)) return null;
    return { x, y };
  }
  return null;
}

function readAnnotation(raw: unknown): Annotation {
  if (raw === null || typeof raw !== 'object') return raw as Annotation;
  const { type, paths } = raw as { type?: unknown; paths?: unknown };
  if (type !== 'ink' || !Array.isArray(paths)) return raw as Annotation;
  // A stroke that is not an array is malformed and skipped entirely.
  const strokes = paths.filter((stroke): stroke is unknown[] => Array.isArray(stroke));
  return {
    ...(raw as Annotation),
    paths: strokes.map((stroke) =>
      stroke.map(readInkPoint).filter((point): point is AnnotationPoint => point !== null)
    ),
  } as Annotation;
}

/**
 * Parses a serialised annotation set, accepting ink points in object form
 * (`{"x": …, "y": …}`), array form (`[x, y]`) or a mix of both, and returns
 * every ink point in object form. Malformed ink points, and strokes that are not
 * arrays, are skipped. Values are not rounded.
 *
 * @throws If `json` cannot be parsed or has no `annotations` array.
 */
export function parseAnnotations(json: string): AnnotationsData {
  const data = JSON.parse(json) as { annotations?: unknown } | null;
  if (!Array.isArray(data?.annotations)) {
    throw new Error('Annotation set JSON has no "annotations" array');
  }
  return { version: 1, annotations: data.annotations.map(readAnnotation) };
}
