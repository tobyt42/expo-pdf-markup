import * as pdfjs from 'pdfjs-dist';
import { act, type ReactNode } from 'react';

import type { ExpoPdfMarkupViewProps } from '../ExpoPdfMarkup.types';
import ExpoPdfMarkupView from '../ExpoPdfMarkupView.web';

// The repo has no @types/react-dom, so type the small part of react-dom/client used here.
type Root = { render(element: ReactNode): void; unmount(): void };
const { createRoot } = require('react-dom/client') as { createRoot(el: Element): Root };

// These cases drive the real DOM, so they only run in the jsdom (Web) project.
const describeDom = typeof document === 'undefined' ? describe.skip : describe;

const VIEW_WIDTH = 400;
const VIEW_HEIGHT = 600;

// ---------------------------------------------------------------------------
// DOM stand-ins for what jsdom lacks
// ---------------------------------------------------------------------------

const resizeObservers = new Set<FakeResizeObserver>();

class FakeResizeObserver {
  private targets: Element[] = [];
  constructor(private readonly callback: ResizeObserverCallback) {
    resizeObservers.add(this);
  }
  observe(target: Element) {
    this.targets.push(target);
    this.fire(VIEW_WIDTH, VIEW_HEIGHT);
  }
  unobserve() {}
  disconnect() {
    resizeObservers.delete(this);
  }
  fire(width: number, height: number) {
    const entries = this.targets.map(
      (target) => ({ target, contentRect: { width, height } }) as unknown as ResizeObserverEntry
    );
    this.callback(entries, this as unknown as ResizeObserver);
  }
}

const intersectionObservers = new Set<FakeIntersectionObserver>();

class FakeIntersectionObserver {
  constructor(private readonly callback: IntersectionObserverCallback) {
    intersectionObservers.add(this);
  }
  observe() {}
  unobserve() {}
  disconnect() {
    intersectionObservers.delete(this);
  }
  takeRecords() {
    return [];
  }
  /** Reports `target` as the topmost visible page. */
  show(target: Element) {
    const entry = { target, isIntersecting: true, boundingClientRect: { top: 0 } };
    this.callback([entry as unknown as IntersectionObserverEntry], this as never);
  }
}

/** Simulates the reader scrolling continuous mode until `page` is at the top. */
function scrollContinuousTo(page: number) {
  const target = view().querySelector(`[data-pdf-page="${page}"]`)!;
  act(() => {
    for (const observer of intersectionObservers) observer.show(target);
  });
}

function setPageCount(numPages: number) {
  const page = {
    getViewport: jest.fn().mockReturnValue({ width: 612, height: 792 }),
    render: jest.fn().mockReturnValue({ promise: Promise.resolve(), cancel: jest.fn() }),
    cleanup: jest.fn(),
  };
  const doc = {
    numPages,
    getPage: jest.fn().mockResolvedValue(page),
    loadingTask: { destroy: jest.fn() },
  };
  (pdfjs.getDocument as jest.Mock).mockReturnValue({ promise: Promise.resolve(doc) });
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

let container: HTMLDivElement;
let root: Root;

async function flush() {
  await act(async () => {
    for (let i = 0; i < 10; i++) await Promise.resolve();
  });
}

async function render(props: Partial<ExpoPdfMarkupViewProps>) {
  await act(async () => {
    root.render(<ExpoPdfMarkupView source="test.pdf" {...props} />);
  });
  await flush();
}

function view(): HTMLElement {
  return container.firstElementChild as HTMLElement;
}

function pointer(type: string, x: number, y: number, target: Element = view()) {
  const event = new MouseEvent(type, { bubbles: true, cancelable: true, clientX: x, clientY: y });
  Object.assign(event, { pointerId: 1, pointerType: 'touch', isPrimary: true });
  act(() => {
    target.dispatchEvent(event);
  });
}

function finishAnimations() {
  act(() => {
    jest.advanceTimersByTime(1000);
  });
}

function drag(fromX: number, toX: number, y = VIEW_HEIGHT / 2, target: Element = view()) {
  pointer('pointerdown', fromX, y, target);
  const steps = 5;
  for (let i = 1; i <= steps; i++) {
    pointer('pointermove', fromX + ((toX - fromX) * i) / steps, y, target);
  }
  pointer('pointerup', toX, y, target);
}

function swipe(fromX: number, toX: number, y = VIEW_HEIGHT / 2) {
  drag(fromX, toX, y);
  finishAnimations();
}

function tap(x: number, y = VIEW_HEIGHT / 2, target: Element = view()) {
  pointer('pointerdown', x, y, target);
  pointer('pointerup', x, y, target);
  finishAnimations();
}

function shownPage(): number {
  return Number(view().getAttribute('data-page'));
}

function visiblePages(): number[] {
  return Array.from(view().querySelectorAll('[data-book-slot]'))
    .filter((slot) => !slot.hasAttribute('aria-hidden'))
    .map((slot) => Number(slot.getAttribute('data-book-slot')));
}

function pageStrip(): HTMLElement {
  return view().firstElementChild!.firstElementChild as HTMLElement;
}

function resize(width: number, height: number) {
  act(() => {
    for (const observer of resizeObservers) observer.fire(width, height);
  });
}

function zoomIn() {
  for (let i = 0; i < 10; i++) {
    act(() => {
      view().dispatchEvent(
        new WheelEvent('wheel', { bubbles: true, cancelable: true, ctrlKey: true, deltaY: -100 })
      );
    });
  }
  finishAnimations();
}

function reportedPages(onPageChanged: jest.Mock): number[] {
  return onPageChanged.mock.calls.map((call) => call[0].nativeEvent.page);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describeDom('ExpoPdfMarkupView (web) book mode', () => {
  beforeEach(() => {
    Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
    jest.useFakeTimers({ doNotFake: ['queueMicrotask', 'nextTick'] });
    resizeObservers.clear();
    intersectionObservers.clear();
    Object.assign(globalThis, {
      ResizeObserver: FakeResizeObserver,
      IntersectionObserver: FakeIntersectionObserver,
      DOMRect: class {
        constructor(
          public x = 0,
          public y = 0,
          public width = 0,
          public height = 0
        ) {}
      },
    });
    HTMLCanvasElement.prototype.getContext = jest.fn().mockReturnValue(null);
    Element.prototype.setPointerCapture = jest.fn();
    Element.prototype.scrollIntoView = jest.fn();
    setPageCount(5);
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
  });

  afterEach(() => {
    act(() => root.unmount());
    container.remove();
    jest.useRealTimers();
  });

  it('swiping left turns to the next page and reports it once', async () => {
    const onPageChanged = jest.fn();
    await render({ displayMode: 'book', onPageChanged });
    onPageChanged.mockClear();

    swipe(300, 100);

    expect(reportedPages(onPageChanged)).toEqual([1]);
  });
  it('shows one page, fitted to the whole view', async () => {
    await render({ displayMode: 'book' });

    expect(visiblePages()).toEqual([0]);
    const page = view().querySelector('[data-book-slot="0"] [data-pdf-page]') as HTMLElement;
    // 612 x 792 pt into 400 x 600 px: the width is the tighter fit.
    expect(parseFloat(page.style.width)).toBeCloseTo(400);
    expect(parseFloat(page.style.height)).toBeCloseTo((792 * 400) / 612, 0);
  });

  it('fits a page to the height when the view is wide', async () => {
    await render({ displayMode: 'book' });
    resize(1000, 300);

    const page = view().querySelector('[data-book-slot="0"] [data-pdf-page]') as HTMLElement;
    expect(parseFloat(page.style.height)).toBeCloseTo(300);
    expect(parseFloat(page.style.width)).toBeCloseTo((612 * 300) / 792, 0);
  });

  it('reports the first page when the document opens in book mode', async () => {
    const onPageChanged = jest.fn();
    await render({ displayMode: 'book', onPageChanged });

    expect(onPageChanged).toHaveBeenCalledTimes(1);
    expect(onPageChanged.mock.calls[0][0].nativeEvent).toEqual({
      page: 0,
      pageCount: 5,
      pageWidth: 612,
      pageHeight: 792,
    });
  });

  it('swiping right turns back to the previous page', async () => {
    const onPageChanged = jest.fn();
    await render({ displayMode: 'book', page: 2, onPageChanged });
    onPageChanged.mockClear();

    swipe(100, 300);

    expect(reportedPages(onPageChanged)).toEqual([1]);
    expect(shownPage()).toBe(1);
  });

  it('slides the page left for next and right for previous', async () => {
    await render({ displayMode: 'book', page: 2 });

    drag(300, 100);
    // The strip moves a whole view to the left, bringing in the next page from the right.
    expect(pageStrip().style.transform).toBe(`translateX(${-2 * VIEW_WIDTH}px)`);
    expect(pageStrip().style.transition).toContain('transform');
    finishAnimations();
    expect(shownPage()).toBe(3);
    expect(pageStrip().style.transform).toBe(`translateX(${-VIEW_WIDTH}px)`);

    drag(100, 300);
    expect(pageStrip().style.transform).toBe('translateX(0px)');
    finishAnimations();
    expect(shownPage()).toBe(2);
  });

  it('a short or mostly vertical drag does not turn the page', async () => {
    const onPageChanged = jest.fn();
    await render({ displayMode: 'book', page: 2, onPageChanged });
    onPageChanged.mockClear();

    swipe(200, 180);
    pointer('pointerdown', 200, 100);
    pointer('pointermove', 140, 400);
    pointer('pointerup', 140, 400);
    finishAnimations();

    expect(onPageChanged).not.toHaveBeenCalled();
    expect(shownPage()).toBe(2);
  });

  it('tapping the outer quarter turns the page, and a tap in the middle does not', async () => {
    const onPageChanged = jest.fn();
    await render({ displayMode: 'book', page: 2, onPageChanged });
    onPageChanged.mockClear();

    tap(VIEW_WIDTH - 20);
    expect(reportedPages(onPageChanged)).toEqual([3]);

    tap(20);
    expect(reportedPages(onPageChanged)).toEqual([3, 2]);

    tap(VIEW_WIDTH / 2);
    tap(VIEW_WIDTH * 0.26);
    tap(VIEW_WIDTH * 0.74);
    expect(reportedPages(onPageChanged)).toEqual([3, 2]);
  });

  it('edge zones are at least 44 px wide on a narrow view', async () => {
    const onPageChanged = jest.fn();
    await render({ displayMode: 'book', page: 2, onPageChanged });
    resize(120, 600);
    onPageChanged.mockClear();

    tap(40); // inside 44 px, though outside the outer quarter (30 px)
    expect(reportedPages(onPageChanged)).toEqual([1]);

    tap(60);
    expect(reportedPages(onPageChanged)).toEqual([1]);
  });

  it('bounces at the first page without turning or reporting', async () => {
    const onPageChanged = jest.fn();
    await render({ displayMode: 'book', onPageChanged });
    onPageChanged.mockClear();

    drag(100, 300);
    // Past the first page the strip springs back to rest.
    expect(pageStrip().style.transform).toBe(`translateX(${-VIEW_WIDTH}px)`);
    finishAnimations();
    tap(20);

    expect(onPageChanged).not.toHaveBeenCalled();
    expect(shownPage()).toBe(0);
    expect(pageStrip().style.transform).toBe(`translateX(${-VIEW_WIDTH}px)`);
  });

  it('bounces at the last page and never wraps round', async () => {
    const onPageChanged = jest.fn();
    await render({ displayMode: 'book', page: 4, onPageChanged });
    onPageChanged.mockClear();

    swipe(300, 100);
    tap(VIEW_WIDTH - 20);

    expect(onPageChanged).not.toHaveBeenCalled();
    expect(shownPage()).toBe(4);
  });

  it('never turns a one-page PDF', async () => {
    setPageCount(1);
    const onPageChanged = jest.fn();
    await render({ displayMode: 'book', onPageChanged });
    onPageChanged.mockClear();

    swipe(300, 100);
    swipe(100, 300);
    tap(VIEW_WIDTH - 20);
    tap(20);

    expect(onPageChanged).not.toHaveBeenCalled();
    expect(visiblePages()).toEqual([0]);
  });

  it('page jumps straight to that page and reports it', async () => {
    const onPageChanged = jest.fn();
    await render({ displayMode: 'book', onPageChanged });
    onPageChanged.mockClear();

    await render({ displayMode: 'book', page: 3, onPageChanged });

    expect(reportedPages(onPageChanged)).toEqual([3]);
    expect(visiblePages()).toEqual([3]);
  });

  it('a quick second turn starts from the page the first was going to', async () => {
    const onPageChanged = jest.fn();
    await render({ displayMode: 'book', onPageChanged });
    onPageChanged.mockClear();

    drag(300, 100);
    drag(300, 100);
    finishAnimations();

    expect(reportedPages(onPageChanged)).toEqual([1, 2]);
    expect(shownPage()).toBe(2);
  });

  it('switching between continuous and book keeps the current page', async () => {
    const scrollIntoView = jest.fn();
    Element.prototype.scrollIntoView = scrollIntoView;
    const onPageChanged = jest.fn();
    await render({ displayMode: 'book', onPageChanged });
    swipe(300, 100);
    swipe(300, 100);
    onPageChanged.mockClear();

    await render({ displayMode: 'continuous', onPageChanged });
    expect(view().querySelectorAll('[data-pdf-page]')).toHaveLength(5);
    expect(scrollIntoView.mock.contexts.at(-1)).toBe(view().querySelector('[data-pdf-page="2"]'));

    await render({ displayMode: 'book', onPageChanged });
    expect(visiblePages()).toEqual([2]);
    expect(onPageChanged).not.toHaveBeenCalled();
  });

  it('switching to book shows the page the reader scrolled to in continuous mode', async () => {
    const onPageChanged = jest.fn();
    await render({ onPageChanged });
    scrollContinuousTo(3);
    expect(reportedPages(onPageChanged).at(-1)).toBe(3);
    onPageChanged.mockClear();

    await render({ displayMode: 'book', onPageChanged });

    expect(visiblePages()).toEqual([3]);
    expect(onPageChanged).not.toHaveBeenCalled();
  });

  it('resizing keeps the current page without reloading the document', async () => {
    const onPageChanged = jest.fn();
    await render({ displayMode: 'book', onPageChanged });
    swipe(300, 100);
    onPageChanged.mockClear();
    const loads = (pdfjs.getDocument as jest.Mock).mock.calls.length;

    resize(800, 500);
    await flush();

    expect(visiblePages()).toEqual([1]);
    expect(onPageChanged).not.toHaveBeenCalled();
    expect((pdfjs.getDocument as jest.Mock).mock.calls.length).toBe(loads);
  });

  it('zoomed in beyond fit, a swipe pans and edge taps do not turn', async () => {
    const onPageChanged = jest.fn();
    await render({ displayMode: 'book', page: 2, onPageChanged });
    onPageChanged.mockClear();
    zoomIn();

    let scrollLeft = 300;
    Object.defineProperty(view(), 'scrollLeft', {
      configurable: true,
      get: () => scrollLeft,
      set: (value: number) => {
        scrollLeft = value;
      },
    });
    swipe(300, 100);
    tap(VIEW_WIDTH - 20);
    tap(20);

    expect(onPageChanged).not.toHaveBeenCalled();
    expect(scrollLeft).toBe(500);
  });

  it('turning by page resets the new page to fit', async () => {
    const onPageChanged = jest.fn();
    await render({ displayMode: 'book', page: 2, onPageChanged });
    zoomIn();
    await render({ displayMode: 'book', page: 3, onPageChanged });
    onPageChanged.mockClear();

    // Back at fit, so edge taps turn again.
    tap(VIEW_WIDTH - 20);
    expect(reportedPages(onPageChanged)).toEqual([4]);
  });

  it.each(['ink', 'highlight', 'underline', 'text', 'stamp', 'move', 'eraser'] as const)(
    'with the %s tool active, swipes and edge taps never turn the page',
    async (annotationMode) => {
      const onPageChanged = jest.fn();
      await render({
        displayMode: 'book',
        page: 2,
        annotationMode,
        stampText: 'S',
        onPageChanged,
        onTextInputRequested: async () => null,
      });
      onPageChanged.mockClear();
      const canvas = view().querySelectorAll('[data-book-slot="2"] canvas')[1]!;

      drag(300, 100, VIEW_HEIGHT / 2, canvas);
      drag(100, 300, VIEW_HEIGHT / 2, canvas);
      finishAnimations();
      tap(VIEW_WIDTH - 20, VIEW_HEIGHT / 2, canvas);
      tap(20, VIEW_HEIGHT / 2, canvas);
      await flush();

      expect(onPageChanged).not.toHaveBeenCalled();
      expect(shownPage()).toBe(2);
    }
  );

  it('markup lands on the page where it was drawn', async () => {
    const onAnnotationsChanged = jest.fn();
    await render({ displayMode: 'book', page: 3, annotationMode: 'ink', onAnnotationsChanged });
    const canvas = view().querySelectorAll('[data-book-slot="3"] canvas')[1]!;

    drag(100, 200, 100, canvas);

    const json = onAnnotationsChanged.mock.calls.at(-1)[0].nativeEvent.annotations;
    expect(JSON.parse(json).annotations).toEqual([
      expect.objectContaining({ type: 'ink', page: 3 }),
    ]);
  });

  it('continuous mode still shows every page and ignores swipes and taps', async () => {
    const onPageChanged = jest.fn();
    await render({ onPageChanged });
    onPageChanged.mockClear();

    swipe(300, 100);
    tap(VIEW_WIDTH - 20);
    expect(onPageChanged).not.toHaveBeenCalled();

    scrollContinuousTo(1);
    expect(reportedPages(onPageChanged)).toEqual([1]);
    expect(view().getAttribute('data-display-mode')).toBe('continuous');
    expect(view().querySelectorAll('[data-pdf-page]')).toHaveLength(5);
    expect(view().querySelector('[data-book-slot]')).toBeNull();
    expect(view().style.overflowY).toBe('scroll');
  });
});
