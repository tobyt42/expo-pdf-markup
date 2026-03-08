import type { Annotation, AnnotationPoint } from '../../ExpoPdfMarkup.types';
import {
  canvasToPdf,
  canvasRectToPdfBounds,
  distanceToSegment,
  hitTestAnnotation,
  parseAnnotations,
  pdfBoundsToCanvas,
  pdfToCanvas,
  serializeAnnotations,
} from '../../web/annotationUtils';

// ---------------------------------------------------------------------------
// Coordinate round-trips
// ---------------------------------------------------------------------------

describe('canvasToPdf / pdfToCanvas round-trip', () => {
  it('returns identity for arbitrary point', () => {
    const scale = 1.5;
    const pageHeight = 792;
    const original: AnnotationPoint = { x: 100, y: 200 };
    const canvas = pdfToCanvas(original.x, original.y, scale, pageHeight);
    const back = canvasToPdf(canvas.x, canvas.y, scale, pageHeight);
    expect(back.x).toBeCloseTo(original.x);
    expect(back.y).toBeCloseTo(original.y);
  });

  it('y=0 in PDF maps to bottom of canvas', () => {
    const scale = 1;
    const pageHeight = 100;
    const { y } = pdfToCanvas(0, 0, scale, pageHeight);
    expect(y).toBe(100); // canvas y = (pageHeight - 0) * scale
  });

  it('y=pageHeight in PDF maps to top of canvas', () => {
    const scale = 1;
    const pageHeight = 100;
    const { y } = pdfToCanvas(0, pageHeight, scale, pageHeight);
    expect(y).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// pdfBoundsToCanvas
// ---------------------------------------------------------------------------

describe('pdfBoundsToCanvas', () => {
  it('flips y correctly: page 100pt tall, bounds at y=20 height=10 → canvasTop=70', () => {
    const scale = 1;
    const pageHeight = 100;
    const result = pdfBoundsToCanvas({ x: 0, y: 20, width: 50, height: 10 }, scale, pageHeight);
    // canvasTop = (pageHeight - bounds.y - bounds.height) * scale = (100 - 20 - 10) * 1 = 70
    expect(result.y).toBe(70);
    expect(result.x).toBe(0);
    expect(result.width).toBe(50);
    expect(result.height).toBe(10);
  });

  it('scales dimensions', () => {
    const scale = 2;
    const pageHeight = 100;
    const result = pdfBoundsToCanvas({ x: 10, y: 10, width: 20, height: 30 }, scale, pageHeight);
    expect(result.x).toBe(20);
    expect(result.width).toBe(40);
    expect(result.height).toBe(60);
  });
});

// ---------------------------------------------------------------------------
// canvasRectToPdfBounds
// ---------------------------------------------------------------------------

describe('canvasRectToPdfBounds', () => {
  it('inverts the y-flip', () => {
    const scale = 1;
    const pageHeight = 100;
    // Canvas rect: top=70, bottom=80 → PDF: y=20, height=10
    const result = canvasRectToPdfBounds(0, 70, 50, 80, scale, pageHeight);
    expect(result.y).toBeCloseTo(20);
    expect(result.height).toBeCloseTo(10);
    expect(result.x).toBeCloseTo(0);
    expect(result.width).toBeCloseTo(50);
  });

  it('round-trips with pdfBoundsToCanvas', () => {
    const scale = 1.5;
    const pageHeight = 792;
    const original = { x: 50, y: 100, width: 200, height: 50 };
    const canvasRect = pdfBoundsToCanvas(original, scale, pageHeight);
    const back = canvasRectToPdfBounds(
      canvasRect.x,
      canvasRect.y,
      canvasRect.x + canvasRect.width,
      canvasRect.y + canvasRect.height,
      scale,
      pageHeight
    );
    expect(back.x).toBeCloseTo(original.x);
    expect(back.y).toBeCloseTo(original.y);
    expect(back.width).toBeCloseTo(original.width);
    expect(back.height).toBeCloseTo(original.height);
  });
});

// ---------------------------------------------------------------------------
// distanceToSegment
// ---------------------------------------------------------------------------

describe('distanceToSegment', () => {
  it('returns 0 for a point on the segment', () => {
    const a: AnnotationPoint = { x: 0, y: 0 };
    const b: AnnotationPoint = { x: 10, y: 0 };
    expect(distanceToSegment({ x: 5, y: 0 }, a, b)).toBeCloseTo(0);
  });

  it('returns perpendicular distance for a point beside the segment', () => {
    const a: AnnotationPoint = { x: 0, y: 0 };
    const b: AnnotationPoint = { x: 10, y: 0 };
    expect(distanceToSegment({ x: 5, y: 3 }, a, b)).toBeCloseTo(3);
  });

  it('returns distance to nearest endpoint when point is past end', () => {
    const a: AnnotationPoint = { x: 0, y: 0 };
    const b: AnnotationPoint = { x: 10, y: 0 };
    expect(distanceToSegment({ x: 15, y: 0 }, a, b)).toBeCloseTo(5);
  });

  it('handles degenerate segment (a == b) by returning distance to point', () => {
    const a: AnnotationPoint = { x: 3, y: 4 };
    const b: AnnotationPoint = { x: 3, y: 4 };
    expect(distanceToSegment({ x: 0, y: 0 }, a, b)).toBeCloseTo(5);
  });
});

// ---------------------------------------------------------------------------
// hitTestAnnotation
// ---------------------------------------------------------------------------

const inkAnnotation: Annotation = {
  id: 'ink1',
  type: 'ink',
  page: 0,
  color: '#000000',
  lineWidth: 2,
  paths: [
    [
      { x: 0, y: 0 },
      { x: 100, y: 0 },
    ],
  ],
};

const highlightAnnotation: Annotation = {
  id: 'hl1',
  type: 'highlight',
  page: 0,
  color: '#FFFF00',
  bounds: { x: 50, y: 50, width: 100, height: 20 },
};

describe('hitTestAnnotation', () => {
  it('hits ink annotation within tolerance', () => {
    const result = hitTestAnnotation({ x: 50, y: 5 }, [inkAnnotation], 0);
    expect(result?.id).toBe('ink1');
  });

  it('misses ink annotation outside tolerance', () => {
    const result = hitTestAnnotation({ x: 50, y: 20 }, [inkAnnotation], 0);
    expect(result).toBeNull();
  });

  it('hits bounds annotation inside rect', () => {
    const result = hitTestAnnotation({ x: 100, y: 60 }, [highlightAnnotation], 0);
    expect(result?.id).toBe('hl1');
  });

  it('misses bounds annotation outside rect', () => {
    const result = hitTestAnnotation({ x: 200, y: 60 }, [highlightAnnotation], 0);
    expect(result).toBeNull();
  });

  it('ignores annotations on other pages', () => {
    const result = hitTestAnnotation({ x: 100, y: 60 }, [highlightAnnotation], 1);
    expect(result).toBeNull();
  });

  it('returns topmost annotation when multiple overlap', () => {
    const hl2: Annotation = {
      id: 'hl2',
      type: 'highlight',
      page: 0,
      color: '#FF0000',
      bounds: { x: 50, y: 50, width: 100, height: 20 },
    };
    const result = hitTestAnnotation({ x: 100, y: 60 }, [highlightAnnotation, hl2], 0);
    expect(result?.id).toBe('hl2');
  });
});

// ---------------------------------------------------------------------------
// parseAnnotations
// ---------------------------------------------------------------------------

describe('parseAnnotations', () => {
  it('returns empty data for undefined', () => {
    const result = parseAnnotations(undefined);
    expect(result.annotations).toHaveLength(0);
    expect(result.version).toBe(1);
  });

  it('returns empty data for empty string', () => {
    expect(parseAnnotations('').annotations).toHaveLength(0);
  });

  it('returns empty data for malformed JSON', () => {
    expect(parseAnnotations('{not json}').annotations).toHaveLength(0);
  });

  it('parses valid annotations JSON', () => {
    const data = serializeAnnotations({ version: 1, annotations: [highlightAnnotation] });
    const result = parseAnnotations(data);
    expect(result.annotations).toHaveLength(1);
    expect(result.annotations[0].id).toBe('hl1');
  });

  it('deduplicates by id — last wins', () => {
    const a1: Annotation = { ...highlightAnnotation, color: '#FF0000' };
    const a2: Annotation = { ...highlightAnnotation, color: '#00FF00' };
    const data = serializeAnnotations({ version: 1, annotations: [a1, a2] });
    const result = parseAnnotations(data);
    expect(result.annotations).toHaveLength(1);
    expect(result.annotations[0].color).toBe('#00FF00');
  });
});
