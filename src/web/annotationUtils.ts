import type {
  Annotation,
  AnnotationBounds,
  AnnotationPoint,
  AnnotationsData,
} from '../ExpoPdfMarkup.types';
import type { PdfPageMeta } from './types';

// ---------------------------------------------------------------------------
// Coordinate transforms
// ---------------------------------------------------------------------------

/** Convert canvas pixel coords → PDF user-space coords (y-up) */
export function canvasToPdf(
  canvasX: number,
  canvasY: number,
  scale: number,
  pageHeight: number
): AnnotationPoint {
  return {
    x: canvasX / scale,
    y: pageHeight - canvasY / scale,
  };
}

/** Convert PDF user-space coords (y-up) → canvas pixel coords */
export function pdfToCanvas(
  pdfX: number,
  pdfY: number,
  scale: number,
  pageHeight: number
): { x: number; y: number } {
  return {
    x: pdfX * scale,
    y: (pageHeight - pdfY) * scale,
  };
}

/**
 * Convert a PDF bounds rect (y-up, y = bottom edge) → canvas rect (y-down, y = top edge).
 * All values are in CSS pixels (not physical pixels).
 */
export function pdfBoundsToCanvas(
  bounds: AnnotationBounds,
  scale: number,
  pageHeight: number
): { x: number; y: number; width: number; height: number } {
  return {
    x: bounds.x * scale,
    y: (pageHeight - bounds.y - bounds.height) * scale,
    width: bounds.width * scale,
    height: bounds.height * scale,
  };
}

/**
 * Convert a canvas drag rect (minX/Y, maxX/Y in CSS pixels) → PDF bounds (y-up).
 * `bounds.y` is the bottom edge in PDF space, consistent with iOS/Android.
 */
export function canvasRectToPdfBounds(
  minX: number,
  minY: number,
  maxX: number,
  maxY: number,
  scale: number,
  pageHeight: number
): AnnotationBounds {
  return {
    x: minX / scale,
    y: pageHeight - maxY / scale,
    width: (maxX - minX) / scale,
    height: (maxY - minY) / scale,
  };
}

// ---------------------------------------------------------------------------
// Hit testing (ported from AnnotationHitTester.kt)
// ---------------------------------------------------------------------------

export function distanceToSegment(
  point: AnnotationPoint,
  a: AnnotationPoint,
  b: AnnotationPoint
): number {
  const dx = b.x - a.x;
  const dy = b.y - a.y;
  const lenSq = dx * dx + dy * dy;
  if (lenSq === 0) {
    const px = point.x - a.x;
    const py = point.y - a.y;
    return Math.sqrt(px * px + py * py);
  }
  let t = ((point.x - a.x) * dx + (point.y - a.y) * dy) / lenSq;
  t = Math.max(0, Math.min(1, t));
  const projX = a.x + t * dx;
  const projY = a.y + t * dy;
  const ex = point.x - projX;
  const ey = point.y - projY;
  return Math.sqrt(ex * ex + ey * ey);
}

function boundsContains(bounds: AnnotationBounds, point: AnnotationPoint): boolean {
  return (
    point.x >= bounds.x &&
    point.x <= bounds.x + bounds.width &&
    point.y >= bounds.y &&
    point.y <= bounds.y + bounds.height
  );
}

/** Return the topmost annotation hit at pdfPoint on pageIndex, or null. */
export function hitTestAnnotation(
  pdfPoint: AnnotationPoint,
  annotations: Annotation[],
  pageIndex: number
): Annotation | null {
  const onPage = annotations.filter((a) => a.page === pageIndex);
  for (let i = onPage.length - 1; i >= 0; i--) {
    const annotation = onPage[i];
    if (annotation.type === 'ink') {
      const tolerance = Math.max(annotation.lineWidth ?? 2, 10);
      const paths = annotation.paths ?? [];
      for (const stroke of paths) {
        if (stroke.length === 1) {
          const dx = pdfPoint.x - stroke[0].x;
          const dy = pdfPoint.y - stroke[0].y;
          if (Math.sqrt(dx * dx + dy * dy) <= tolerance) return annotation;
        }
        for (let j = 0; j < stroke.length - 1; j++) {
          if (distanceToSegment(pdfPoint, stroke[j], stroke[j + 1]) <= tolerance) {
            return annotation;
          }
        }
      }
    } else {
      const bounds = annotation.bounds;
      if (bounds && boundsContains(bounds, pdfPoint)) return annotation;
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Canvas drawing (mirrors AnnotationRenderer.kt)
// ---------------------------------------------------------------------------

/**
 * Draw all annotations for pageIndex onto ctx.
 * meta.scale is CSS-pixels-per-PDF-point; canvas backing = CSS * devicePixelRatio,
 * but the caller should have called ctx.scale(dpr, dpr) so we work in CSS pixels here.
 */
export function drawAnnotationsOnCanvas(
  ctx: CanvasRenderingContext2D,
  annotations: Annotation[],
  pageIndex: number,
  meta: PdfPageMeta
): void {
  const { scale, pdfHeight } = meta;
  for (const annotation of annotations) {
    if (annotation.page !== pageIndex) continue;
    switch (annotation.type) {
      case 'ink': {
        const paths = annotation.paths ?? [];
        ctx.save();
        ctx.strokeStyle = annotation.color;
        ctx.lineWidth = (annotation.lineWidth ?? 2) * scale;
        ctx.lineCap = 'round';
        ctx.lineJoin = 'round';
        for (const stroke of paths) {
          if (stroke.length === 0) continue;
          ctx.beginPath();
          for (let i = 0; i < stroke.length; i++) {
            const { x, y } = pdfToCanvas(stroke[i].x, stroke[i].y, scale, pdfHeight);
            if (i === 0) ctx.moveTo(x, y);
            else ctx.lineTo(x, y);
          }
          ctx.stroke();
        }
        ctx.restore();
        break;
      }
      case 'highlight': {
        const bounds = annotation.bounds;
        if (!bounds) break;
        const rect = pdfBoundsToCanvas(bounds, scale, pdfHeight);
        ctx.save();
        ctx.globalAlpha = annotation.alpha ?? 0.5;
        ctx.fillStyle = annotation.color;
        ctx.fillRect(rect.x, rect.y, rect.width, rect.height);
        ctx.restore();
        break;
      }
      case 'underline': {
        const bounds = annotation.bounds;
        if (!bounds) break;
        // Underline sits at the bottom of bounds (PDF y = bounds.y = bottom edge)
        const left = bounds.x * scale;
        const bottom = (pdfHeight - bounds.y) * scale;
        const right = left + bounds.width * scale;
        ctx.save();
        ctx.strokeStyle = annotation.color;
        ctx.lineWidth = scale;
        ctx.beginPath();
        ctx.moveTo(left, bottom);
        ctx.lineTo(right, bottom);
        ctx.stroke();
        ctx.restore();
        break;
      }
      case 'text':
      case 'freeText': {
        const bounds = annotation.bounds;
        const text = annotation.contents;
        if (!bounds || !text) break;
        const fontSize = (annotation.fontSize ?? 16) * scale;
        ctx.save();
        ctx.fillStyle = annotation.color;
        ctx.font = `${fontSize}px sans-serif`;
        const canvasTop = (pdfHeight - bounds.y - bounds.height) * scale;
        ctx.fillText(text, bounds.x * scale, canvasTop + fontSize);
        ctx.restore();
        break;
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Serialization
// ---------------------------------------------------------------------------

export function parseAnnotations(json?: string): AnnotationsData {
  if (!json) return { version: 1, annotations: [] };
  try {
    const data = JSON.parse(json) as AnnotationsData;
    if (!Array.isArray(data?.annotations)) return { version: 1, annotations: [] };
    // Deduplicate by id — last wins
    const seen = new Map<string, Annotation>();
    for (const a of data.annotations) {
      seen.set(a.id, a);
    }
    return { version: 1, annotations: Array.from(seen.values()) };
  } catch {
    return { version: 1, annotations: [] };
  }
}

export function serializeAnnotations(data: AnnotationsData): string {
  return JSON.stringify(data);
}

export function newAnnotationId(): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID();
  }
  return Math.random().toString(36).slice(2) + Date.now().toString(36);
}
