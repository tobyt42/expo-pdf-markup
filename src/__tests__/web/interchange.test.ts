import arrayFixture from '../../../fixtures/annotations-v1-array.json';
import fixture from '../../../fixtures/annotations-v1.json';
import {
  drawAnnotationsOnCanvas,
  hitTestAnnotation,
  parseAnnotationsOrEmpty,
  serializeAnnotations,
  translateAnnotation,
} from '../../web/annotationUtils';

// The same v1 payload is loaded by PDFKit and Android tests. Coordinates refer to
// the displayed 600 x 840 pt visible page, independent of its native crop origin.
describe('shared v1 annotation interchange', () => {
  it('preserves placement, identity, content and style over repeated save/reopen cycles', () => {
    let data = parseAnnotationsOrEmpty(JSON.stringify(fixture));
    for (let cycle = 0; cycle < 5; cycle++) {
      data = parseAnnotationsOrEmpty(serializeAnnotations(data));
    }
    expect(data).toEqual(fixture);
  });

  it('decodes the array-form fixture, including a mixed-form ink stroke, to the object-form set', () => {
    expect(parseAnnotationsOrEmpty(JSON.stringify(arrayFixture))).toEqual(fixture);
  });

  it('renders the shared marks at fixed visible-page positions', () => {
    const data = parseAnnotationsOrEmpty(JSON.stringify(fixture));
    const ctx = {
      save: jest.fn(),
      restore: jest.fn(),
      beginPath: jest.fn(),
      moveTo: jest.fn(),
      lineTo: jest.fn(),
      stroke: jest.fn(),
      fillRect: jest.fn(),
      fillText: jest.fn(),
    } as unknown as CanvasRenderingContext2D;
    drawAnnotationsOnCanvas(ctx, data.annotations, 0, {
      pdfWidth: 600,
      pdfHeight: 840,
      scale: 2,
      canvasWidth: 1200,
      canvasHeight: 1680,
    });

    expect(ctx.moveTo).toHaveBeenNthCalledWith(1, 80, 1480);
    expect(ctx.lineTo).toHaveBeenNthCalledWith(1, 240, 1360);
    expect(ctx.lineTo).toHaveBeenNthCalledWith(2, 360, 1420);
    expect(ctx.fillRect).toHaveBeenCalledWith(120, 1032, 360, 48);
    expect(ctx.moveTo).toHaveBeenNthCalledWith(2, 160, 920);
    expect(ctx.lineTo).toHaveBeenNthCalledWith(3, 480, 920);
    expect(ctx.fillText).toHaveBeenCalledWith('Shared note', 200, 732);
    expect(ctx.fillText).toHaveBeenCalledWith('Visible page', 200, 596);
    expect(ctx.fillText).toHaveBeenCalledWith('♫', 88, 232);
    expect(ctx.fillText).toHaveBeenCalledWith('★', 588, 232);
    expect(ctx.fillText).toHaveBeenCalledWith('🎵', 1108, 232);
  });

  it('moves and hit-tests every category without accumulating a crop offset', () => {
    const data = parseAnnotationsOrEmpty(JSON.stringify(fixture));
    const targets = [
      { x: 120, y: 160 },
      { x: 150, y: 312 },
      { x: 160, y: 390 },
      { x: 220, y: 470 },
      { x: 220, y: 540 },
      { x: 44, y: 724 },
      { x: 294, y: 724 },
      { x: 554, y: 724 },
    ];
    data.annotations.forEach((annotation, index) => {
      const target = targets[index]!;
      expect(hitTestAnnotation(target, data.annotations, 0)?.id).toBe(annotation.id);
      const moved = translateAnnotation(annotation, 12, -16);
      expect(hitTestAnnotation({ x: target.x + 12, y: target.y - 16 }, [moved], 0)?.id).toBe(
        annotation.id
      );
      expect(translateAnnotation(moved, -12, 16)).toEqual(annotation);
    });
  });
});
