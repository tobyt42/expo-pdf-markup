import arrayFixture from '../../fixtures/annotations-v1-array.json';
import fixture from '../../fixtures/annotations-v1.json';
import { parseAnnotations } from '../index';
import type { AnnotationPointArray, InkAnnotation } from '../index';

// The entry point pulls in the native view on iOS/Android.
jest.mock('expo', () => ({
  requireNativeView: jest.fn(() => 'MockNativeView'),
  requireNativeModule: jest.fn(() => ({ provideTextInput: jest.fn() })),
}));

function inkSet(paths: unknown[][]): string {
  return JSON.stringify({
    version: 1,
    annotations: [
      { id: 'ink', type: 'ink', page: 0, color: '#000000', lineWidth: 2, paths },
      {
        id: 'hl',
        type: 'highlight',
        page: 0,
        color: '#FFFF00',
        bounds: { x: 1.23456, y: 2, width: 3, height: 4 },
      },
    ],
  });
}

function inkPaths(json: string) {
  return (parseAnnotations(json).annotations[0] as InkAnnotation).paths;
}

describe('parseAnnotations (public)', () => {
  it('reads an object-form annotation set unchanged', () => {
    expect(parseAnnotations(JSON.stringify(fixture))).toEqual(fixture);
  });

  it('reads array form and mixed forms within one stroke as object form', () => {
    expect(parseAnnotations(JSON.stringify(arrayFixture))).toEqual(fixture);
  });

  it('reads a stroke written entirely in array form', () => {
    const point: AnnotationPointArray = [10, 20];
    expect(inkPaths(inkSet([[point, [30, 40]]]))).toEqual([
      [
        { x: 10, y: 20 },
        { x: 30, y: 40 },
      ],
    ]);
  });

  it('skips malformed ink points and keeps the rest of the stroke and set', () => {
    const json = inkSet([
      [[1, 2], [3], { x: 4 }, ['5', 6], { x: 7, y: 8 }, [9, 10, 11], null, 'x', [12, 13]],
    ]);
    expect(inkPaths(json)).toEqual([
      [
        { x: 1, y: 2 },
        { x: 7, y: 8 },
        { x: 12, y: 13 },
      ],
    ]);
    expect(parseAnnotations(json).annotations[1]!.id).toBe('hl');
  });

  it('skips a stroke that is not an array and keeps the other strokes and the set', () => {
    const json = inkSet([[[1, 2]], 'not a stroke' as never, [{ x: 3, y: 4 }]]);
    expect(inkPaths(json)).toEqual([[{ x: 1, y: 2 }], [{ x: 3, y: 4 }]]);
    expect(parseAnnotations(json).annotations[1]!.id).toBe('hl');
  });

  it('does not round ink points or bounds', () => {
    const json = inkSet([[[307.6921296296296, 462.6087962962961], { x: 0.123456, y: 0.987654 }]]);
    expect(inkPaths(json)).toEqual([
      [
        { x: 307.6921296296296, y: 462.6087962962961 },
        { x: 0.123456, y: 0.987654 },
      ],
    ]);
    expect(parseAnnotations(json).annotations[1]).toMatchObject({
      bounds: { x: 1.23456, y: 2, width: 3, height: 4 },
    });
  });

  it('throws on JSON that cannot be parsed', () => {
    expect(() => parseAnnotations('{not json}')).toThrow();
  });

  it('throws when there is no annotations array', () => {
    expect(() => parseAnnotations('{"version":1}')).toThrow();
    expect(() => parseAnnotations('{"version":1,"annotations":{}}')).toThrow();
    expect(() => parseAnnotations('null')).toThrow();
  });
});
