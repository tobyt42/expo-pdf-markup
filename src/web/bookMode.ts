import type { AnnotationMode } from '../ExpoPdfMarkup.types';

/** Which way a turn goes. `'next'` is always forward in the document, whatever the layout direction. */
export type TurnDirection = 'next' | 'previous';

/** Minimum width of an edge tap zone, in CSS px. */
export const MIN_EDGE_ZONE_PX = 44;
/** Share of the view's width that each edge tap zone covers. */
export const EDGE_ZONE_FRACTION = 0.25;
/** Pointer travel (CSS px) below which a press counts as a tap rather than a drag. */
export const TAP_SLOP_PX = 10;
/** Share of the view's width a slow swipe has to travel to turn the page, as on iOS and Android. */
export const SWIPE_TURN_FRACTION = 0.25;
/**
 * A release faster than this (CSS px per ms) turns the page even after a short drag. It's the
 * 500 pt/s (iOS) and 500 dp/s (Android) fling speed.
 */
export const FLING_VELOCITY_PX_PER_MS = 0.5;
/** How far back (ms) the pointer's movement counts towards its release speed. */
export const VELOCITY_WINDOW_MS = 100;
/** How much of the drag the page follows past the first or last page. */
export const EDGE_RESISTANCE = 0.3;
/** How far (CSS px) the page nudges when a tap or key bounces at either end. */
export const BOUNCE_PX = 40;

/**
 * Turn policy for book mode swipes and edge taps: they turn the page only with no markup tool
 * active, and when the page isn't zoomed in beyond fit. Hardware keys don't go through this.
 */
export function canGestureTurn(annotationMode: AnnotationMode, zoom: number): boolean {
  return annotationMode === 'none' && zoom <= 1;
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
 * Where the page strip moves to slide `distance` px in `direction`: left (negative) for next,
 * right for previous, so the page that comes in enters from the side the turn heads towards.
 */
export function slideOffsetFor(direction: TurnDirection, distance: number): number {
  return direction === 'next' ? -distance : distance;
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

/**
 * The turn a finished drag asks for, or `null` to settle back. `velocityX` is the horizontal speed
 * at release in px/ms (negative = leftwards). Swipe left always means next, whatever the layout
 * direction. A slow release turns once the drag passes a quarter of the view; a fast fling turns
 * in its own direction unless it flicks back against the drag. A mostly vertical drag never turns.
 */
export function classifySwipe(
  dx: number,
  dy: number,
  viewWidth: number,
  velocityX: number
): TurnDirection | null {
  if (Math.abs(dx) < Math.abs(dy)) return null;
  const threshold = viewWidth * SWIPE_TURN_FRACTION;
  const fromDrag = dx <= -threshold ? 'next' : dx >= threshold ? 'previous' : null;
  if (Math.abs(velocityX) < FLING_VELOCITY_PX_PER_MS) return fromDrag;
  const fromFling = velocityX < 0 ? 'next' : 'previous';
  const dragOpposes = (fromFling === 'next' && dx > 0) || (fromFling === 'previous' && dx < 0);
  return dragOpposes ? null : fromFling;
}

/** A pointer position at a moment, for working out the release speed. */
export type PointerSample = { x: number; t: number };

/**
 * Horizontal speed (px/ms) over the samples from the last {@link VELOCITY_WINDOW_MS}, or 0 when
 * they span no time. `samples` are oldest first, ending with the release.
 */
export function releaseVelocityX(samples: PointerSample[]): number {
  const last = samples[samples.length - 1];
  if (!last) return 0;
  const first = samples.find((s) => last.t - s.t <= VELOCITY_WINDOW_MS) ?? last;
  const dt = last.t - first.t;
  return dt > 0 ? (last.x - first.x) / dt : 0;
}
