import * as pdfjs from 'pdfjs-dist';

import { getEmbeddedAnnotations } from '../../ExpoPdfMarkupModule.web';

// Access the mock internals set up in src/__mocks__/pdfjs-dist.ts
const mockGetDocument = pdfjs.getDocument as jest.Mock;

// Helper to build a fresh mock document with custom pages
function buildMockDoc(pages: { annotations: object[] }[]) {
  const mockPages = pages.map((p) => ({
    getAnnotations: jest.fn().mockResolvedValue(p.annotations),
    cleanup: jest.fn(),
  }));
  const doc = {
    numPages: pages.length,
    getPage: jest.fn((n: number) => Promise.resolve(mockPages[n - 1])),
    destroy: jest.fn(),
  };
  mockGetDocument.mockReturnValueOnce({ promise: Promise.resolve(doc) });
  return doc;
}

beforeEach(() => {
  jest.clearAllMocks();
});

describe('getEmbeddedAnnotations (web)', () => {
  it('returns empty annotations for an empty PDF', async () => {
    buildMockDoc([{ annotations: [] }, { annotations: [] }]);
    const result = await getEmbeddedAnnotations('test.pdf');
    const parsed = JSON.parse(result);
    expect(parsed).toEqual({ version: 1, annotations: [] });
  });

  it('converts a Highlight annotation correctly', async () => {
    buildMockDoc([
      {
        annotations: [
          {
            subtype: 'Highlight',
            rect: [72, 100, 400, 120],
            color: { r: 255, g: 255, b: 0 },
            id: 'hl-1',
          },
        ],
      },
    ]);
    const result = await getEmbeddedAnnotations('test.pdf');
    const { annotations } = JSON.parse(result);
    expect(annotations).toHaveLength(1);
    const ann = annotations[0];
    expect(ann.type).toBe('highlight');
    expect(ann.color).toBe('#FFFF00');
    expect(ann.alpha).toBe(0.5);
    expect(ann.bounds).toEqual({ x: 72, y: 100, width: 328, height: 20 });
    expect(ann.page).toBe(0);
    expect(ann.id).toBe('hl-1');
  });

  it('converts an Ink annotation correctly', async () => {
    buildMockDoc([
      {
        annotations: [
          {
            subtype: 'Ink',
            rect: [0, 0, 100, 100],
            color: { r: 255, g: 0, b: 0 },
            id: 'ink-1',
            inkLists: [
              [
                { x: 10, y: 20 },
                { x: 30, y: 40 },
              ],
            ],
            borderStyle: { width: 3 },
          },
        ],
      },
    ]);
    const result = await getEmbeddedAnnotations('test.pdf');
    const { annotations } = JSON.parse(result);
    expect(annotations).toHaveLength(1);
    const ann = annotations[0];
    expect(ann.type).toBe('ink');
    expect(ann.color).toBe('#FF0000');
    expect(ann.lineWidth).toBe(3);
    expect(ann.paths).toEqual([
      [
        { x: 10, y: 20 },
        { x: 30, y: 40 },
      ],
    ]);
  });

  it('converts a FreeText annotation correctly', async () => {
    buildMockDoc([
      {
        annotations: [
          {
            subtype: 'FreeText',
            rect: [72, 320, 300, 340],
            color: { r: 0, g: 0, b: 0 },
            id: 'ft-1',
            contents: 'Imported from another app',
          },
        ],
      },
    ]);
    const result = await getEmbeddedAnnotations('test.pdf');
    const { annotations } = JSON.parse(result);
    expect(annotations).toHaveLength(1);
    const ann = annotations[0];
    expect(ann.type).toBe('freeText');
    expect(ann.contents).toBe('Imported from another app');
    expect(ann.bounds).toEqual({ x: 72, y: 320, width: 228, height: 20 });
  });

  it('excludes unknown subtypes (e.g. Widget)', async () => {
    buildMockDoc([
      {
        annotations: [{ subtype: 'Widget', rect: [0, 0, 100, 20], color: null, id: 'w-1' }],
      },
    ]);
    const result = await getEmbeddedAnnotations('test.pdf');
    const { annotations } = JSON.parse(result);
    expect(annotations).toHaveLength(0);
  });

  it('generates a non-empty id when raw.id is missing', async () => {
    buildMockDoc([
      {
        annotations: [
          { subtype: 'Highlight', rect: [0, 0, 100, 20], color: { r: 0, g: 0, b: 255 } },
        ],
      },
    ]);
    const result = await getEmbeddedAnnotations('test.pdf');
    const { annotations } = JSON.parse(result);
    expect(annotations[0].id).toBeTruthy();
    expect(annotations[0].id.length).toBeGreaterThan(0);
  });

  it('falls back to #000000 for null color', async () => {
    buildMockDoc([
      {
        annotations: [
          { subtype: 'Highlight', rect: [0, 0, 100, 20], color: null, id: 'null-color' },
        ],
      },
    ]);
    const result = await getEmbeddedAnnotations('test.pdf');
    const { annotations } = JSON.parse(result);
    expect(annotations[0].color).toBe('#000000');
  });

  it('handles multiple pages with correct page indices', async () => {
    buildMockDoc([
      {
        annotations: [
          { subtype: 'Highlight', rect: [0, 0, 100, 20], color: { r: 255, g: 0, b: 0 }, id: 'p0' },
        ],
      },
      {
        annotations: [
          {
            subtype: 'Ink',
            rect: [0, 0, 100, 100],
            color: { r: 0, g: 255, b: 0 },
            id: 'p1',
            inkLists: [],
            borderStyle: { width: 1 },
          },
        ],
      },
    ]);
    const result = await getEmbeddedAnnotations('test.pdf');
    const { annotations } = JSON.parse(result);
    expect(annotations).toHaveLength(2);
    expect(annotations[0].page).toBe(0);
    expect(annotations[1].page).toBe(1);
  });

  it('still processes other pages when one page getAnnotations throws', async () => {
    const page0 = {
      getAnnotations: jest.fn().mockRejectedValue(new Error('page error')),
      cleanup: jest.fn(),
    };
    const page1 = {
      getAnnotations: jest
        .fn()
        .mockResolvedValue([
          { subtype: 'Highlight', rect: [0, 0, 100, 20], color: { r: 0, g: 0, b: 255 }, id: 'ok' },
        ]),
      cleanup: jest.fn(),
    };
    const doc = {
      numPages: 2,
      getPage: jest.fn((n: number) => Promise.resolve(n === 1 ? page0 : page1)),
      destroy: jest.fn(),
    };
    mockGetDocument.mockReturnValueOnce({ promise: Promise.resolve(doc) });

    const result = await getEmbeddedAnnotations('test.pdf');
    const { annotations } = JSON.parse(result);
    expect(annotations).toHaveLength(1);
    expect(annotations[0].page).toBe(1);
    expect(doc.destroy).toHaveBeenCalled();
  });

  it('rejects when getDocument fails', async () => {
    mockGetDocument.mockReturnValueOnce({ promise: Promise.reject(new Error('not found')) });
    await expect(getEmbeddedAnnotations('bad.pdf')).rejects.toThrow('not found');
  });
});
