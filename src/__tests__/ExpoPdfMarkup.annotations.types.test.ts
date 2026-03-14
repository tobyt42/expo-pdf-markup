import type {
  Annotation,
  AnnotationMode,
  AnnotationsData,
  ExpoPdfMarkupViewProps,
  HighlightAnnotation,
  InkAnnotation,
  TextAnnotation,
  UnderlineAnnotation,
} from '../ExpoPdfMarkup.types';

function accept(_props: ExpoPdfMarkupViewProps) {
  // no-op
}

it('annotation props are optional (existing usage still compiles)', () => {
  accept({ source: 'test.pdf' });
  accept({ source: 'test.pdf', page: 0 });
  expect(true).toBe(true);
});

it('accepts valid annotation props', () => {
  accept({
    source: 'test.pdf',
    annotations: '{"version":1,"annotations":[]}',
    annotationMode: 'move',
    annotationColor: '#FF0000',
    annotationLineWidth: 3,
    onAnnotationsChanged: (_e) => {},
  });
  expect(true).toBe(true);
});

it('annotationMode rejects invalid literals', () => {
  accept({
    source: 'test.pdf',
    // @ts-expect-error: 'invalid' is not a valid AnnotationMode
    annotationMode: 'invalid',
  });
  expect(true).toBe(true);
});

it('onAnnotationsChanged event shape is correct', () => {
  accept({
    source: 'test.pdf',
    onAnnotationsChanged: (event) => {
      const _json: string = event.nativeEvent.annotations;
      expect(_json).toBeDefined();
    },
  });
  expect(true).toBe(true);
});

it('annotation discriminated union compiles correctly', () => {
  const ink: InkAnnotation = {
    id: '1',
    type: 'ink',
    page: 0,
    color: '#FF0000',
    lineWidth: 2,
    paths: [[{ x: 0, y: 0 }]],
  };

  const highlight: HighlightAnnotation = {
    id: '2',
    type: 'highlight',
    page: 0,
    color: '#FFFF00',
    bounds: { x: 0, y: 0, width: 100, height: 14 },
  };

  const underline: UnderlineAnnotation = {
    id: '3',
    type: 'underline',
    page: 0,
    color: '#0000FF',
    bounds: { x: 0, y: 0, width: 100, height: 12 },
  };

  const text: TextAnnotation = {
    id: '4',
    type: 'text',
    page: 0,
    color: '#00FF00',
    bounds: { x: 0, y: 0, width: 24, height: 24 },
    contents: 'Note',
  };

  const annotations: Annotation[] = [ink, highlight, underline, text];
  const data: AnnotationsData = { version: 1, annotations };
  const mode: AnnotationMode = 'move';
  expect(data.version).toBe(1);
  expect(data.annotations).toHaveLength(4);
  expect(mode).toBe('move');
});
