import * as pdfjs from 'pdfjs-dist';

import type { Annotation, AnnotationsData } from './ExpoPdfMarkup.types';
import { newAnnotationId, serializeAnnotations } from './web/annotationUtils';

// ---------------------------------------------------------------------------
// Internal pdfjs types (not exported)
// ---------------------------------------------------------------------------

type PdfjsColor = { r: number; g: number; b: number } | null;

type PdfjsAnnotation = {
  subtype: string;
  rect: [number, number, number, number];
  color: PdfjsColor;
  id?: string;
  inkLists?: { x: number; y: number }[][];
  borderStyle?: { width: number };
  contents?: string;
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function pdfjsColorToHex(color: PdfjsColor): string {
  if (!color) return '#000000';
  const r = Math.round(color.r).toString(16).padStart(2, '0');
  const g = Math.round(color.g).toString(16).padStart(2, '0');
  const b = Math.round(color.b).toString(16).padStart(2, '0');
  return `#${r}${g}${b}`.toUpperCase();
}

function pdfjsRectToBounds(rect: [number, number, number, number]): {
  x: number;
  y: number;
  width: number;
  height: number;
} {
  const [x1, y1, x2, y2] = rect;
  return { x: x1, y: y1, width: x2 - x1, height: y2 - y1 };
}

function convertPdfjsAnnotation(raw: PdfjsAnnotation, pageIndex: number): Annotation | null {
  const id = raw.id && raw.id.length > 0 ? raw.id : newAnnotationId();
  const color = pdfjsColorToHex(raw.color);
  const createdAt = Date.now() / 1000;

  switch (raw.subtype) {
    case 'Highlight':
      return {
        id,
        type: 'highlight',
        page: pageIndex,
        color,
        alpha: 0.5,
        bounds: pdfjsRectToBounds(raw.rect),
        createdAt,
      };
    case 'Underline':
      return {
        id,
        type: 'underline',
        page: pageIndex,
        color,
        bounds: pdfjsRectToBounds(raw.rect),
        createdAt,
      };
    case 'Ink':
      return {
        id,
        type: 'ink',
        page: pageIndex,
        color,
        lineWidth: raw.borderStyle?.width ?? 1,
        paths: raw.inkLists ?? [],
        createdAt,
      };
    case 'FreeText':
      return {
        id,
        type: 'freeText',
        page: pageIndex,
        color,
        bounds: pdfjsRectToBounds(raw.rect),
        contents: raw.contents,
        createdAt,
      };
    default:
      return null;
  }
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Extracts annotations already embedded in the PDF
 * and returns them serialized as `AnnotationsData` JSON, ready to pass to the `annotations` prop.
 *
 * @param filePath - URL or path to the PDF file.
 * @returns A JSON string matching the `AnnotationsData` schema (`{ version: 1, annotations: [...] }`).
 */
export async function getEmbeddedAnnotations(filePath: string): Promise<string> {
  const doc = await pdfjs.getDocument(filePath).promise;
  const annotations: Annotation[] = [];
  try {
    for (let i = 0; i < doc.numPages; i++) {
      const page = await doc.getPage(i + 1);
      let rawAnnotations: PdfjsAnnotation[] = [];
      try {
        rawAnnotations = (await page.getAnnotations()) as PdfjsAnnotation[];
      } catch {
        // skip page
      }
      page.cleanup();
      for (const raw of rawAnnotations) {
        const converted = convertPdfjsAnnotation(raw, i);
        if (converted) annotations.push(converted);
      }
    }
  } finally {
    doc.destroy();
  }
  return serializeAnnotations({ version: 1, annotations } as AnnotationsData);
}
