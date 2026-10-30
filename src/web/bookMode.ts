import type { AnnotationMode, DisplayMode } from '../ExpoPdfMarkup.types';
import type { PdfPageMeta } from './types';

/** Which way a turn goes. `'next'` is always forward in the document, whatever the layout direction. */
export type TurnDirection = 'next' | 'previous';

export type PageSize = { pdfWidth: number; pdfHeight: number };

/** Minimum width of an edge tap zone, in CSS px. */
export const MIN_EDGE_ZONE_PX = 44;
/** Share of the view's width that each edge tap zone covers. */
export const EDGE_ZONE_FRACTION = 0.25;
/** Pointer travel (CSS px) below which a press counts as a tap rather than a drag. */
export const TAP_SLOP_PX = 10;
/** Horizontal travel (CSS px) a swipe needs before it turns the page. */
export const MIN_SWIPE_PX = 50;
/** Share of the view's width a swipe can cover instead of {@link MIN_SWIPE_PX}, whichever is less. */
export const SWIPE_FRACTION = 0.2;
/** How much of the drag the page follows past the first or last page. */
export const EDGE_RESISTANCE = 0.3;
/** How far (CSS px) the page nudges when a tap or key bounces at either end. */
export const BOUNCE_PX = 40;

/**
 * Turn policy for swipes and edge taps: they turn the page only in book mode, with no markup
 * tool active, and when the page isn't zoomed in beyond fit. Hardware keys don't go through this.
 */
export function canGestureTurn(
  displayMode: DisplayMode,
  annotationMode: AnnotationMode,
  zoom: number
): boolean {
  return displayMode === 'book' && annotationMode === 'none' && zoom <= 1;
}

const KEY_TURNS: Record<string, TurnDirection> = {
  ArrowRight: 'next',
  ArrowDown: 'next',
  PageDown: 'next',
  ArrowLeft: 'previous',
  ArrowUp: 'previous',
  PageUp: 'previous',
};

/**
 * The turn a hardware key asks for in book mode, or `null` for a key that doesn't turn.
 * Right, Down and Page Down go forward; Left, Up and Page Up go back. Space isn't mapped.
 * Keys turn whatever the zoom or markup mode, so they don't go through {@link canGestureTurn}.
 */
export function keyTurnFor(key: string): TurnDirection | null {
  return KEY_TURNS[key] ?? null;
}

/** `<input>` types that don't take typed text, so arrow keys there can still turn the page. */
const NON_TEXT_INPUT_TYPES = new Set([
  'button',
  'checkbox',
  'color',
  'file',
  'hidden',
  'image',
  'radio',
  'range',
  'reset',
  'submit',
]);

/**
 * Whether `el` takes typed text: a text `<input>`, a `<textarea>`, a `<select>` or anything
 * contenteditable. Keys pressed there belong to it, never to the page turn.
 */
export function isTextEntry(el: Element | null): boolean {
  if (!el) return false;
  const tag = el.tagName;
  if (tag === 'TEXTAREA' || tag === 'SELECT') return true;
  if (tag === 'INPUT') return !NON_TEXT_INPUT_TYPES.has((el as HTMLInputElement).type);
  return el.closest('[contenteditable]:not([contenteditable="false"])') != null;
}

/**
 * The page a turn lands on, or `null` when it would go before the first page or past the last.
 * Nothing wraps round.
 */
export function resolveTurn(
  current: number,
  direction: TurnDirection,
  pageCount: number
): number | null {
  const target = direction === 'next' ? current + 1 : current - 1;
  return target >= 0 && target < pageCount ? target : null;
}

/** Width of each edge tap zone: the outer quarter of the view, at least 44 CSS px. */
export function edgeZoneWidth(viewWidth: number): number {
  return Math.min(viewWidth / 2, Math.max(MIN_EDGE_ZONE_PX, viewWidth * EDGE_ZONE_FRACTION));
}

/** The turn an edge tap at `x` (CSS px from the view's left edge) asks for, or `null` in the middle. */
export function classifyTap(x: number, viewWidth: number): TurnDirection | null {
  const zone = edgeZoneWidth(viewWidth);
  if (x < zone) return 'previous';
  if (x > viewWidth - zone) return 'next';
  return null;
}

/** The turn a finished drag asks for, or `null` if it was too short or mostly vertical. */
export function classifySwipe(dx: number, dy: number, viewWidth: number): TurnDirection | null {
  const threshold = Math.min(MIN_SWIPE_PX, viewWidth * SWIPE_FRACTION);
  if (Math.abs(dx) < threshold || Math.abs(dx) < Math.abs(dy)) return null;
  // Swipe left (finger moves towards smaller x) always means next.
  return dx < 0 ? 'next' : 'previous';
}

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
