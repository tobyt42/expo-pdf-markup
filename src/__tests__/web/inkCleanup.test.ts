import expectedObjectForm from '../../../fixtures/ink-cleanup-expected-object.json';
import cleanupInput from '../../../fixtures/ink-cleanup-input.json';
import v1Fixture from '../../../fixtures/annotations-v1.json';
import type { Annotation, AnnotationsData, InkAnnotation } from '../../ExpoPdfMarkup.types';
import { serializeAnnotations, translateAnnotation } from '../../web/annotationUtils';

const input = (): AnnotationsData => JSON.parse(JSON.stringify(cleanupInput)) as AnnotationsData;

const inkSet = (paths: InkAnnotation['paths']): AnnotationsData => ({
  version: 1,
  annotations: [{ id: 'ink', type: 'ink', page: 0, color: '#000000', lineWidth: 2, paths }],
});

const writtenPaths = (data: AnnotationsData): InkAnnotation['paths'] =>
  (JSON.parse(serializeAnnotations(data)).annotations[0] as InkAnnotation).paths;

// Every number written as an ink point coordinate, as raw JSON text.
const inkCoordinateTexts = (json: string): string[] =>
  Array.from(json.matchAll(/"paths":(\[(?:\[[^\]]*\],?)*\])/g)).flatMap((match) =>
    Array.from(match[1]!.matchAll(/"[xy]":(-?[0-9.eE+-]+)/g), (m) => m[1]!)
  );

// The same clean-up fixture pair is loaded by the PDFKit and Android serialiser tests.
describe('ink point clean-up when writing an annotation set', () => {
  it('writes the shared clean-up fixture exactly as expected in object form', () => {
    expect(JSON.parse(serializeAnnotations(input()))).toEqual(expectedObjectForm);
  });

  it('writes every ink coordinate as its 0.1 pt rounding with at most one decimal digit', () => {
    const texts = inkCoordinateTexts(serializeAnnotations(input()));

    expect(texts).toEqual([
      '307.7',
      '462.6',
      '1.8',
      '12.3',
      '100',
      '100',
      '0',
      '-1.3',
      '0.1',
      '2.7',
      '50',
      '60',
      '50',
      '60',
      '5',
      '5',
      '5',
      '5',
      '10.1',
      '21',
      '200.1',
      '301',
      '200.2',
      '300.9',
      '200.1',
      '301',
    ]);
    for (const text of texts) {
      expect(text).toMatch(/^-?(0|[1-9][0-9]*)(\.[1-9])?$/);
      const value = Number(text);
      expect(Math.round(value * 10) / 10).toBe(value);
    }
  });

  it('writes a stroke that collapses to one ink point as two identical ink points', () => {
    expect(
      writtenPaths(
        inkSet([
          [
            { x: 12.01, y: 8.04 },
            { x: 11.99, y: 7.96 },
          ],
        ])
      )
    ).toEqual([
      [
        { x: 12, y: 8 },
        { x: 12, y: 8 },
      ],
    ]);
  });

  it('leaves strokes that already have fewer than two ink points that short', () => {
    expect(writtenPaths(inkSet([[{ x: 3.14159, y: 2.71828 }], []]))).toEqual([
      [{ x: 3.1, y: 2.7 }],
      [],
    ]);
  });

  it('keeps a repeat of an earlier ink point when it is not consecutive', () => {
    expect(
      writtenPaths(
        inkSet([
          [
            { x: 1, y: 1 },
            { x: 2, y: 2 },
            { x: 1.04, y: 0.96 },
          ],
        ])
      )
    ).toEqual([
      [
        { x: 1, y: 1 },
        { x: 2, y: 2 },
        { x: 1, y: 1 },
      ],
    ]);
  });

  it('writes bounds and every non-ink field byte-for-byte unchanged', () => {
    const others: Annotation[] = [
      {
        id: 'h',
        type: 'highlight',
        page: 2,
        color: '#FFCC00',
        alpha: 0.333333,
        bounds: { x: 60.123456789, y: 300.987654321, width: 180.55555, height: 24.04 },
        createdAt: 1741340001.5,
      },
      {
        id: 'u',
        type: 'underline',
        page: 0,
        color: '#2244CC',
        bounds: { x: 80.05, y: 380.15, width: 160.25, height: 20.0001 },
      },
      {
        id: 't',
        type: 'text',
        page: 0,
        color: '#114422',
        bounds: { x: 100.06, y: 450.94, width: 240.123, height: 40.987 },
        contents: 'Note',
        fontSize: 16.25,
        fontFamily: 'Helvetica',
      },
      {
        id: 's',
        type: 'stamp',
        page: 0,
        color: '#332299',
        bounds: { x: 20.123456, y: 700.987654, width: 48.05, height: 48.15 },
        text: '★',
      },
    ];
    const ink: InkAnnotation = {
      id: 'i',
      type: 'ink',
      page: 1,
      color: '#CC2244',
      lineWidth: 2.345,
      paths: [
        [
          { x: 1.23, y: 4.56 },
          { x: 7.89, y: 0.12 },
        ],
      ],
      createdAt: 1741340000.25,
    };

    const json = serializeAnnotations({ version: 1, annotations: [...others, ink] });

    for (const annotation of others) {
      expect(json).toContain(JSON.stringify(annotation));
    }
    expect(json).toContain(
      '{"id":"i","type":"ink","page":1,"color":"#CC2244","lineWidth":2.345,"paths":[[{"x":1.2,"y":4.6},{"x":7.9,"y":0.1}]],"createdAt":1741340000.25}'
    );
  });

  it('keeps full precision in memory while cleaning up the written set', () => {
    const data = input();
    const before = JSON.stringify(data);

    serializeAnnotations(data);

    expect(JSON.stringify(data)).toBe(before);
  });

  it('keeps each written ink point within 0.05 pt of its true position over repeated moves', () => {
    let annotation: Annotation = inkSet([
      [
        { x: 100.01, y: 200.02 },
        { x: 150.07, y: 250.03 },
      ],
    ]).annotations[0]!;
    let totalX = 0;
    let totalY = 0;

    for (let move = 0; move < 50; move++) {
      annotation = translateAnnotation(annotation, 0.37, -0.23);
      totalX += 0.37;
      totalY -= 0.23;
      const written = writtenPaths({ version: 1, annotations: [annotation] });

      expect(Math.abs(written[0]![0]!.x - (100.01 + totalX))).toBeLessThanOrEqual(0.05 + 1e-9);
      expect(Math.abs(written[0]![0]!.y - (200.02 + totalY))).toBeLessThanOrEqual(0.05 + 1e-9);
      expect(Math.abs(written[0]![1]!.x - (150.07 + totalX))).toBeLessThanOrEqual(0.05 + 1e-9);
      expect(Math.abs(written[0]![1]!.y - (250.03 + totalY))).toBeLessThanOrEqual(0.05 + 1e-9);
    }
  });

  it('writes the existing v1 fixture unchanged', () => {
    expect(serializeAnnotations(v1Fixture as AnnotationsData)).toBe(JSON.stringify(v1Fixture));
  });
});
