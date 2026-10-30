import type { DisplayMode } from '../ExpoPdfMarkup.types';
import type { PageSize, PdfPageMeta } from './types';

/**
 * Layout for every page. Continuous mode fits each page to the view's width. Book mode fits the
 * whole page into the view, falling back to width when the height isn't known yet.
 */
export function computePageMetas(
  sizes: PageSize[],
  viewWidth: number,
  viewHeight: number,
  displayMode: DisplayMode,
  dpr: number
): PdfPageMeta[] {
  if (viewWidth <= 0) return [];
  return sizes.map(({ pdfWidth, pdfHeight }) => {
    const widthScale = viewWidth / pdfWidth;
    const scale =
      displayMode === 'book' && viewHeight > 0
        ? Math.min(widthScale, viewHeight / pdfHeight)
        : widthScale;
    return {
      pdfWidth,
      pdfHeight,
      scale,
      canvasWidth: Math.round(pdfWidth * scale * dpr),
      canvasHeight: Math.round(pdfHeight * scale * dpr),
    };
  });
}
