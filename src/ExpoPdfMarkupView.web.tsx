import * as pdfjs from 'pdfjs-dist';
import type { PDFDocumentProxy, PDFPageProxy } from 'pdfjs-dist';
import * as React from 'react';

import type {
  Annotation,
  AnnotationMode,
  ExpoPdfMarkupViewProps,
  TextAnnotation,
  TextInputRequest,
} from './ExpoPdfMarkup.types';
import {
  clampAnnotationTranslation,
  canvasRectToPdfBounds,
  canvasToPdf,
  drawAnnotationsOnCanvas,
  hitTestAnnotation,
  newAnnotationId,
  parseAnnotations,
  serializeAnnotations,
  translateAnnotation,
} from './web/annotationUtils';
import {
  BOUNCE_PX,
  EDGE_RESISTANCE,
  TAP_SLOP_PX,
  isTextEntry,
  keyTurnFor,
  canGestureTurn,
  classifySwipe,
  classifyTap,
  computePageMetas,
  resolveTurn,
  type PageSize,
  type TurnDirection,
} from './web/bookMode';
import type { PdfPageMeta } from './web/types';

// Configure pdfjs worker once at module level (consumers can override before mounting)
if (!pdfjs.GlobalWorkerOptions.workerSrc) {
  // Default: served from public/ by withPdfMarkup() in metro.js.
  // Relative URL so the worker resolves correctly regardless of the sub-path
  // the app is hosted at (e.g. /example/ on GitHub Pages).
  // Override with setPdfJsWorkerSrc() if using a different bundler or CDN.
  pdfjs.GlobalWorkerOptions.workerSrc = './pdf.worker.min.mjs';
}

/** Allow consumers to override the pdfjs worker URL before mounting the view. */
export function setPdfJsWorkerSrc(url: string): void {
  pdfjs.GlobalWorkerOptions.workerSrc = url;
}

// pdfjs-dist v6 decodes image data (JBIG2/CCITT fax, JPEG2000, ICC) in
// WebAssembly and must be told where the .wasm files live. withPdfMarkup() in
// metro.js copies them to public/wasm/. Relative URL so the worker resolves it
// regardless of the sub-path the app is hosted at. Override with
// setPdfJsWasmUrl() for a different bundler or CDN.
let wasmUrl = './wasm/';

/** Allow consumers to override the pdfjs WebAssembly directory URL before mounting the view. */
export function setPdfJsWasmUrl(url: string): void {
  wasmUrl = url;
}

// ---------------------------------------------------------------------------
// Zoom constants
// ---------------------------------------------------------------------------

const MIN_ZOOM = 1;
const MAX_ZOOM = 5;

// ---------------------------------------------------------------------------
// PageView
// ---------------------------------------------------------------------------

type PageViewProps = {
  doc: PDFDocumentProxy;
  pageIndex: number;
  meta: PdfPageMeta;
  annotations: Annotation[];
  annotationMode: AnnotationMode;
  annotationColor: string;
  annotationLineWidth: number;
  stampText?: string;
  stampSize: number;
  zoomLevel: number;
  onAnnotationAdded: (annotation: Annotation) => void;
  onAnnotationRemoved: (id: string) => void;
  onAnnotationUpdated: (annotation: Annotation) => void;
  onTextInputRequested: (
    request: TextInputRequest,
    annotation: TextAnnotation | null
  ) => void | Promise<void>;
  containerRef: (el: HTMLDivElement | null) => void;
};

function PageView({
  doc,
  pageIndex,
  meta,
  annotations,
  annotationMode,
  annotationColor,
  annotationLineWidth,
  stampText,
  stampSize,
  zoomLevel,
  onAnnotationAdded,
  onAnnotationRemoved,
  onAnnotationUpdated,
  onTextInputRequested,
  containerRef,
}: PageViewProps) {
  const pdfCanvasRef = React.useRef<HTMLCanvasElement>(null);
  const annotCanvasRef = React.useRef<HTMLCanvasElement>(null);
  const pageRef = React.useRef<PDFPageProxy | null>(null);
  const renderTaskRef = React.useRef<ReturnType<PDFPageProxy['render']> | null>(null);
  const pointerDownRef = React.useRef(false);
  const inkPointsRef = React.useRef<{ x: number; y: number }[]>([]);
  const dragStartRef = React.useRef<{ x: number; y: number } | null>(null);
  const dragCurrentRef = React.useRef<{ x: number; y: number } | null>(null);
  const moveTargetRef = React.useRef<Annotation | null>(null);
  const moveStartPdfRef = React.useRef<{ x: number; y: number } | null>(null);
  const movePreviewRef = React.useRef<Annotation | null>(null);

  const dpr = typeof window === 'undefined' ? 1 : window.devicePixelRatio || 1;
  const cssWidth = meta.canvasWidth / dpr;
  const cssHeight = meta.canvasHeight / dpr;
  const showEditingHighlights = annotationMode === 'move' || annotationMode === 'eraser';

  // Render PDF page onto pdfCanvas
  React.useEffect(() => {
    let cancelled = false;
    async function render() {
      if (!pdfCanvasRef.current) return;
      renderTaskRef.current?.cancel();
      renderTaskRef.current = null;
      const page = await doc.getPage(pageIndex + 1);
      if (cancelled) {
        page.cleanup();
        return;
      }
      pageRef.current = page;
      const canvas = pdfCanvasRef.current;
      if (!canvas) return;
      canvas.width = meta.canvasWidth;
      canvas.height = meta.canvasHeight;
      const ctx = canvas.getContext('2d');
      if (!ctx) return;
      const viewport = page.getViewport({ scale: meta.scale * dpr });
      const task = page.render({ canvas: null, canvasContext: ctx, viewport });
      renderTaskRef.current = task;
      try {
        await task.promise;
      } catch {
        // Render cancelled — ignore
      }
    }
    render();
    return () => {
      cancelled = true;
      renderTaskRef.current?.cancel();
    };
  }, [doc, pageIndex, meta, dpr]);

  // Draw annotations on annotCanvas
  const redrawAnnotations = React.useCallback(
    (liveInkPoints?: { x: number; y: number }[], dragRect?: DOMRect) => {
      const canvas = annotCanvasRef.current;
      if (!canvas) return;
      canvas.width = meta.canvasWidth;
      canvas.height = meta.canvasHeight;
      const ctx = canvas.getContext('2d');
      if (!ctx) return;
      ctx.scale(dpr, dpr);
      drawAnnotationsOnCanvas(ctx, annotations, pageIndex, meta, {
        highlightAnnotations: showEditingHighlights,
        previewAnnotationId: moveTargetRef.current?.id ?? null,
        previewAnnotation: movePreviewRef.current,
      });
      // Live ink preview
      if (liveInkPoints && liveInkPoints.length > 1) {
        ctx.save();
        ctx.strokeStyle = annotationColor;
        ctx.lineWidth = annotationLineWidth * meta.scale;
        ctx.lineCap = 'round';
        ctx.lineJoin = 'round';
        ctx.beginPath();
        for (let i = 0; i < liveInkPoints.length; i++) {
          const pt = liveInkPoints[i];
          if (!pt) continue;
          if (i === 0) ctx.moveTo(pt.x, pt.y);
          else ctx.lineTo(pt.x, pt.y);
        }
        ctx.stroke();
        ctx.restore();
      }
      // Live drag rect preview (highlight/underline)
      if (dragRect) {
        ctx.save();
        ctx.strokeStyle = annotationColor;
        ctx.lineWidth = 1;
        ctx.setLineDash([4, 4]);
        ctx.strokeRect(dragRect.x, dragRect.y, dragRect.width, dragRect.height);
        ctx.restore();
      }
    },
    [annotations, pageIndex, meta, dpr, annotationColor, annotationLineWidth, showEditingHighlights]
  );

  React.useEffect(() => {
    // CSS @font-face fonts (e.g. loaded via expo-font on web) may not be available to canvas
    // until explicitly requested via document.fonts.load(). Collect the unique font families
    // used by text annotations on this page and load them before drawing.
    const fontFamilies = [
      ...new Set(
        annotations
          .filter(
            (a): a is TextAnnotation =>
              a.page === pageIndex && (a.type === 'text' || a.type === 'freeText')
          )
          .map((a) => a.fontFamily)
          .filter((f): f is string => Boolean(f))
      ),
    ];
    if (fontFamilies.length > 0 && typeof document !== 'undefined') {
      Promise.all(fontFamilies.map((f) => document.fonts.load(`16px ${f}`))).finally(() =>
        redrawAnnotations()
      );
    } else {
      redrawAnnotations();
    }
  }, [redrawAnnotations, annotations, pageIndex]);

  function getCanvasPoint(e: React.PointerEvent<HTMLCanvasElement>): { x: number; y: number } {
    const rect = (e.currentTarget as HTMLCanvasElement).getBoundingClientRect();
    return { x: (e.clientX - rect.left) / zoomLevel, y: (e.clientY - rect.top) / zoomLevel };
  }

  function handlePointerDown(e: React.PointerEvent<HTMLCanvasElement>) {
    if (annotationMode === 'none') return;
    const pt = getCanvasPoint(e);
    if (annotationMode === 'ink') {
      e.currentTarget.setPointerCapture(e.pointerId);
      pointerDownRef.current = true;
      inkPointsRef.current = [pt];
    } else if (annotationMode === 'highlight' || annotationMode === 'underline') {
      e.currentTarget.setPointerCapture(e.pointerId);
      pointerDownRef.current = true;
      dragStartRef.current = pt;
      dragCurrentRef.current = pt;
    } else if (annotationMode === 'move') {
      const pdfPoint = canvasToPdf(pt.x, pt.y, meta.scale, meta.pdfHeight);
      const hit = hitTestAnnotation(pdfPoint, annotations, pageIndex);
      if (!hit) return;
      e.currentTarget.setPointerCapture(e.pointerId);
      pointerDownRef.current = true;
      moveTargetRef.current = hit;
      moveStartPdfRef.current = pdfPoint;
      movePreviewRef.current = hit;
      redrawAnnotations();
    }
  }

  function handlePointerMove(e: React.PointerEvent<HTMLCanvasElement>) {
    if (!pointerDownRef.current) return;
    const pt = getCanvasPoint(e);
    if (annotationMode === 'ink') {
      inkPointsRef.current.push(pt);
      redrawAnnotations(inkPointsRef.current);
    } else if (annotationMode === 'highlight' || annotationMode === 'underline') {
      dragCurrentRef.current = pt;
      const start = dragStartRef.current!;
      const minX = Math.min(start.x, pt.x);
      const minY = Math.min(start.y, pt.y);
      const w = Math.abs(pt.x - start.x);
      const h = Math.abs(pt.y - start.y);
      redrawAnnotations(undefined, new DOMRect(minX, minY, w, h));
    } else if (annotationMode === 'move') {
      const target = moveTargetRef.current;
      const startPdfPoint = moveStartPdfRef.current;
      if (!target || !startPdfPoint) return;
      const pdfPoint = canvasToPdf(pt.x, pt.y, meta.scale, meta.pdfHeight);
      const delta = clampAnnotationTranslation(
        target,
        pdfPoint.x - startPdfPoint.x,
        pdfPoint.y - startPdfPoint.y,
        meta.pdfWidth,
        meta.pdfHeight
      );
      movePreviewRef.current = translateAnnotation(target, delta.x, delta.y);
      redrawAnnotations();
    }
  }

  function handlePointerUp(e: React.PointerEvent<HTMLCanvasElement>) {
    if (
      !pointerDownRef.current &&
      annotationMode !== 'text' &&
      annotationMode !== 'eraser' &&
      annotationMode !== 'stamp'
    )
      return;
    pointerDownRef.current = false;
    const pt = getCanvasPoint(e);
    const { scale, pdfHeight } = meta;

    if (annotationMode === 'ink') {
      const cssPoints = inkPointsRef.current;
      inkPointsRef.current = [];
      if (cssPoints.length === 0) return;
      const pdfPoints = cssPoints.map((p) => canvasToPdf(p.x, p.y, scale, pdfHeight));
      onAnnotationAdded({
        id: newAnnotationId(),
        type: 'ink',
        page: pageIndex,
        color: annotationColor,
        lineWidth: annotationLineWidth,
        paths: [pdfPoints],
        createdAt: Date.now(),
      });
    } else if (annotationMode === 'highlight' || annotationMode === 'underline') {
      const start = dragStartRef.current;
      dragStartRef.current = null;
      dragCurrentRef.current = null;
      if (!start) return;
      const minX = Math.min(start.x, pt.x);
      const minY = Math.min(start.y, pt.y);
      const maxX = Math.max(start.x, pt.x);
      const maxY = Math.max(start.y, pt.y);
      if (maxX - minX < 2 || maxY - minY < 2) return;
      const bounds = canvasRectToPdfBounds(minX, minY, maxX, maxY, scale, pdfHeight);
      if (annotationMode === 'highlight') {
        onAnnotationAdded({
          id: newAnnotationId(),
          type: 'highlight',
          page: pageIndex,
          color: annotationColor,
          alpha: 0.5,
          bounds,
          createdAt: Date.now(),
        });
      } else {
        onAnnotationAdded({
          id: newAnnotationId(),
          type: 'underline',
          page: pageIndex,
          color: annotationColor,
          bounds,
          createdAt: Date.now(),
        });
      }
    } else if (annotationMode === 'move') {
      const target = moveTargetRef.current;
      const preview = movePreviewRef.current;
      moveTargetRef.current = null;
      moveStartPdfRef.current = null;
      movePreviewRef.current = null;
      if (target && preview && preview !== target) {
        onAnnotationUpdated(preview);
      } else {
        redrawAnnotations();
      }
    } else if (annotationMode === 'text') {
      const pdfPoint = canvasToPdf(pt.x, pt.y, scale, pdfHeight);
      const hit = hitTestAnnotation(pdfPoint, annotations, pageIndex);
      const annotation =
        hit?.type === 'text' || hit?.type === 'freeText' ? (hit as TextAnnotation) : null;
      onTextInputRequested(
        {
          mode: annotation ? 'edit' : 'create',
          page: pageIndex,
          point: pdfPoint,
          currentText: annotation?.contents,
        },
        annotation
      );
    } else if (annotationMode === 'eraser') {
      const pdfPoint = canvasToPdf(pt.x, pt.y, scale, pdfHeight);
      const hit = hitTestAnnotation(pdfPoint, annotations, pageIndex);
      if (hit) onAnnotationRemoved(hit.id);
    } else if (annotationMode === 'stamp') {
      if (!stampText) return;
      const pdfPoint = canvasToPdf(pt.x, pt.y, scale, pdfHeight);
      const half = stampSize / 2;
      onAnnotationAdded({
        id: newAnnotationId(),
        type: 'stamp',
        page: pageIndex,
        color: annotationColor,
        bounds: {
          x: pdfPoint.x - half,
          y: pdfPoint.y - half,
          width: stampSize,
          height: stampSize,
        },
        text: stampText,
        createdAt: Date.now(),
      });
    }
  }

  const pointerEvents = annotationMode === 'none' ? 'none' : 'auto';
  const cursor =
    annotationMode === 'move'
      ? 'grab'
      : annotationMode === 'eraser'
        ? 'not-allowed'
        : annotationMode === 'stamp'
          ? 'copy'
          : 'crosshair';

  return (
    <div
      ref={containerRef}
      data-pdf-page={pageIndex}
      style={{ position: 'relative', width: cssWidth, height: cssHeight, margin: '0 auto' }}
    >
      <canvas
        ref={pdfCanvasRef}
        style={{
          position: 'absolute',
          top: 0,
          left: 0,
          width: cssWidth,
          height: cssHeight,
          pointerEvents: 'none',
        }}
      />
      <canvas
        ref={annotCanvasRef}
        style={{
          position: 'absolute',
          top: 0,
          left: 0,
          width: cssWidth,
          height: cssHeight,
          cursor,
          pointerEvents,
        }}
        onPointerDown={handlePointerDown}
        onPointerMove={handlePointerMove}
        onPointerUp={handlePointerUp}
      />
    </div>
  );
}

// ---------------------------------------------------------------------------
// Main component
// ---------------------------------------------------------------------------

/** Duration of the book mode slide, in ms. */
const TURN_DURATION_MS = 250;

type BookGesture = {
  startX: number;
  startY: number;
  lastX: number;
  lastY: number;
  /** `'turn'` drags the page sideways; `'pan'` scrolls a zoomed page. */
  kind: 'turn' | 'pan';
  moved: boolean;
};

export default function ExpoPdfMarkupView(props: ExpoPdfMarkupViewProps) {
  const {
    source,
    displayMode = 'continuous',
    page: propPage,
    backgroundColor = '#f0f0f0',
    annotations: annotationsProp,
    annotationMode = 'none',
    annotationColor = '#FF0000',
    annotationLineWidth = 2,
    annotationFontFamily,
    stampText,
    stampSize = 48,
    onPageChanged,
    onLoadComplete,
    onError,
    onAnnotationsChanged,
    onTextInputRequested,
    style,
  } = props;

  const isBook = displayMode === 'book';
  const scrollContainerRef = React.useRef<HTMLDivElement>(null);
  const [containerSize, setContainerSize] = React.useState({ width: 0, height: 0 });
  const containerWidth = containerSize.width;
  const [doc, setDoc] = React.useState<PDFDocumentProxy | null>(null);
  const [pageSizes, setPageSizes] = React.useState<PageSize[]>([]);
  const [annotations, setAnnotations] = React.useState<Annotation[]>([]);
  const lastAnnotationsJsonRef = React.useRef<string | undefined>(undefined);
  const pageContainerRefs = React.useRef<(HTMLDivElement | null)[]>([]);
  const docRef = React.useRef<PDFDocumentProxy | null>(null);
  const loadingSourceRef = React.useRef<string | null>(null);
  const [zoomLevel, setZoomLevel] = React.useState(1);
  const zoomRef = React.useRef(1);

  // The page the reader is on, shared by both modes so switching mode keeps it. The ref is read
  // by the turn path, so quick turns in a row see the latest page before React re-renders.
  const [currentPage, setCurrentPage] = React.useState(0);
  const currentPageRef = React.useRef(0);
  const lastReportedPageRef = React.useRef(-1);
  // Book mode slide: horizontal offset of the page strip, and whether it animates there.
  const [slide, setSlide] = React.useState({ offset: 0, animated: false });
  const slideOffsetRef = React.useRef(0);
  const turnTimerRef = React.useRef<ReturnType<typeof setTimeout> | null>(null);
  const turnFrameRef = React.useRef<number | null>(null);
  const pendingTurnRef = React.useRef<number | null>(null);
  const gestureRef = React.useRef<BookGesture | null>(null);
  const activePointersRef = React.useRef(new Set<number>());

  const dpr = typeof window === 'undefined' ? 1 : window.devicePixelRatio || 1;
  // Continuous mode ignores the view's height, so a height change doesn't re-lay it out.
  const fitHeight = isBook ? containerSize.height : 0;
  const pageMetas = React.useMemo(
    () => computePageMetas(pageSizes, containerWidth, fitHeight, displayMode, dpr),
    [pageSizes, containerWidth, fitHeight, displayMode, dpr]
  );
  const pageCount = doc ? pageMetas.length : 0;

  /** Records the reader's page and fires `onPageChanged` once per change. */
  const reportPage = React.useCallback(
    (page: number) => {
      currentPageRef.current = page;
      setCurrentPage(page);
      if (!doc || page === lastReportedPageRef.current) return;
      lastReportedPageRef.current = page;
      onPageChanged?.({
        nativeEvent: {
          page,
          pageCount: doc.numPages,
          pageWidth: pageSizes[page]?.pdfWidth ?? 0,
          pageHeight: pageSizes[page]?.pdfHeight ?? 0,
        },
      });
    },
    [doc, pageSizes, onPageChanged]
  );

  const applyAnnotations = React.useCallback(
    (updater: (prev: Annotation[]) => Annotation[]) => {
      setAnnotations((prev) => {
        const next = updater(prev);
        const json = serializeAnnotations({ version: 1, annotations: next });
        lastAnnotationsJsonRef.current = json;
        onAnnotationsChanged?.({ nativeEvent: { annotations: json } });
        return next;
      });
    },
    [onAnnotationsChanged]
  );

  // ResizeObserver → containerSize
  React.useEffect(() => {
    const el = scrollContainerRef.current;
    if (!el) return;
    const ro = new ResizeObserver((entries) => {
      const rect = entries[0]?.contentRect;
      const width = rect?.width ?? 0;
      const height = rect?.height ?? 0;
      setContainerSize((prev) =>
        prev.width === width && prev.height === height ? prev : { width, height }
      );
    });
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  // Pinch-to-zoom: intercept ctrl+wheel (trackpad pinch) and two-finger touch pinch.
  // Zooms only the PDF content, leaving the rest of the UI at 1×.
  React.useEffect(() => {
    const el = scrollContainerRef.current;
    if (!el) return;

    function applyZoom(newZoom: number, originX: number, originY: number) {
      const clamped = Math.max(MIN_ZOOM, Math.min(MAX_ZOOM, newZoom));
      if (clamped === zoomRef.current) return;
      const ratio = clamped / zoomRef.current;
      // Keep the origin point (pointer/pinch centre) stationary in the viewport.
      const nextScrollLeft = (el!.scrollLeft + originX) * ratio - originX;
      const nextScrollTop = (el!.scrollTop + originY) * ratio - originY;
      zoomRef.current = clamped;
      setZoomLevel(clamped);
      // Apply after React re-renders so the CSS zoom is in effect before we set scroll.
      requestAnimationFrame(() => {
        el!.scrollLeft = Math.max(0, nextScrollLeft);
        el!.scrollTop = Math.max(0, nextScrollTop);
      });
    }

    function onWheel(e: WheelEvent) {
      if (!e.ctrlKey) return;
      e.preventDefault();
      const rect = el!.getBoundingClientRect();
      const factor = e.deltaY < 0 ? 1.1 : 1 / 1.1;
      applyZoom(zoomRef.current * factor, e.clientX - rect.left, e.clientY - rect.top);
    }

    let pinchStart: { dist: number; zoom: number; midX: number; midY: number } | null = null;

    function getTouchDist(touches: TouchList): number {
      const dx = touches[0]!.clientX - touches[1]!.clientX;
      const dy = touches[0]!.clientY - touches[1]!.clientY;
      return Math.sqrt(dx * dx + dy * dy);
    }

    function onTouchStart(e: TouchEvent) {
      if (e.touches.length !== 2) return;
      const rect = el!.getBoundingClientRect();
      pinchStart = {
        dist: getTouchDist(e.touches),
        zoom: zoomRef.current,
        midX: (e.touches[0]!.clientX + e.touches[1]!.clientX) / 2 - rect.left,
        midY: (e.touches[0]!.clientY + e.touches[1]!.clientY) / 2 - rect.top,
      };
    }

    function onTouchMove(e: TouchEvent) {
      if (e.touches.length !== 2 || !pinchStart) return;
      e.preventDefault();
      const dist = getTouchDist(e.touches);
      applyZoom(pinchStart.zoom * (dist / pinchStart.dist), pinchStart.midX, pinchStart.midY);
    }

    function onTouchEnd(e: TouchEvent) {
      if (e.touches.length < 2) pinchStart = null;
    }

    el.addEventListener('wheel', onWheel, { passive: false });
    el.addEventListener('touchstart', onTouchStart, { passive: true });
    el.addEventListener('touchmove', onTouchMove, { passive: false });
    el.addEventListener('touchend', onTouchEnd);
    el.addEventListener('touchcancel', onTouchEnd);
    return () => {
      el.removeEventListener('wheel', onWheel);
      el.removeEventListener('touchstart', onTouchStart);
      el.removeEventListener('touchmove', onTouchMove);
      el.removeEventListener('touchend', onTouchEnd);
      el.removeEventListener('touchcancel', onTouchEnd);
    };
  }, []);

  // Load the PDF once the view has a size. Page layout is derived from the page sizes, so
  // resizing the view re-lays out the pages without reloading the document.
  const hasSize = containerWidth > 0;
  React.useEffect(() => {
    if (!source || !hasSize) return;
    let cancelled = false;
    loadingSourceRef.current = source;

    async function load() {
      try {
        const task = pdfjs.getDocument({ url: source, wasmUrl });
        const loadedDoc = await task.promise;
        if (cancelled || loadingSourceRef.current !== source) {
          loadedDoc.loadingTask.destroy();
          return;
        }
        const sizes: PageSize[] = [];
        for (let i = 1; i <= loadedDoc.numPages; i++) {
          const pg = await loadedDoc.getPage(i);
          if (cancelled) {
            pg.cleanup();
            loadedDoc.loadingTask.destroy();
            return;
          }
          const viewport = pg.getViewport({ scale: 1 });
          sizes.push({ pdfWidth: viewport.width, pdfHeight: viewport.height });
          pg.cleanup();
        }
        docRef.current?.loadingTask.destroy();
        docRef.current = loadedDoc;
        currentPageRef.current = 0;
        lastReportedPageRef.current = -1;
        setCurrentPage(0);
        setDoc(loadedDoc);
        setPageSizes(sizes);
        pageContainerRefs.current = new Array(loadedDoc.numPages).fill(null);
        onLoadComplete?.({ nativeEvent: { pageCount: loadedDoc.numPages } });
      } catch (err) {
        if (!cancelled) {
          onError?.({
            nativeEvent: { message: err instanceof Error ? err.message : String(err) },
          });
        }
      }
    }
    load();
    return () => {
      cancelled = true;
    };
  }, [source, hasSize]); // intentionally omit callbacks — they should not re-trigger a PDF load

  // Sync annotations prop → state (guard round-trips)
  React.useEffect(() => {
    if (annotationsProp === lastAnnotationsJsonRef.current) return;
    lastAnnotationsJsonRef.current = annotationsProp;
    const parsed = parseAnnotations(annotationsProp);
    setAnnotations(parsed.annotations);
  }, [annotationsProp]);

  // -------------------------------------------------------------------------
  // Book mode turns
  // -------------------------------------------------------------------------

  const setSlideOffset = React.useCallback((offset: number, animated: boolean) => {
    slideOffsetRef.current = offset;
    setSlide((prev) =>
      prev.offset === offset && prev.animated === animated ? prev : { offset, animated }
    );
  }, []);

  const clearTurnTimer = React.useCallback(() => {
    if (turnTimerRef.current != null) clearTimeout(turnTimerRef.current);
    turnTimerRef.current = null;
    if (turnFrameRef.current != null) cancelAnimationFrame(turnFrameRef.current);
    turnFrameRef.current = null;
  }, []);

  const resetZoom = React.useCallback(() => {
    if (zoomRef.current === 1) return;
    zoomRef.current = 1;
    setZoomLevel(1);
    const el = scrollContainerRef.current;
    if (el) {
      el.scrollLeft = 0;
      el.scrollTop = 0;
    }
  }, []);

  /** Shows `page` straight away, with no slide, and reports it. */
  const showBookPage = React.useCallback(
    (page: number) => {
      clearTurnTimer();
      pendingTurnRef.current = null;
      setSlideOffset(0, false);
      reportPage(page);
    },
    [clearTurnTimer, reportPage, setSlideOffset]
  );

  /** Lands a slide that is still running, so a new turn starts from the page it was going to. */
  const finishPendingTurn = React.useCallback(() => {
    const pending = pendingTurnRef.current;
    if (pending != null) showBookPage(pending);
    else clearTurnTimer();
  }, [clearTurnTimer, showBookPage]);

  /** Slides the page back to rest. From rest it nudges towards `direction` first: the bounce. */
  const bounce = React.useCallback(
    (direction: TurnDirection) => {
      clearTurnTimer();
      if (slideOffsetRef.current === 0) {
        setSlideOffset(direction === 'next' ? -BOUNCE_PX : BOUNCE_PX, true);
        turnTimerRef.current = setTimeout(() => {
          setSlideOffset(0, true);
          turnTimerRef.current = null;
        }, TURN_DURATION_MS / 2);
      } else {
        setSlideOffset(0, true);
      }
    },
    [clearTurnTimer, setSlideOffset]
  );

  /**
   * The one turn path for book mode. Swipes and edge taps call it once the turn policy allows
   * them; hardware keys can call it directly. It resets zoom to fit, slides the page in
   * `direction` (or bounces at either end) and fires `onPageChanged` once the turn lands.
   */
  const turnPage = React.useCallback(
    (direction: TurnDirection) => {
      if (!isBook || pageCount === 0) return;
      finishPendingTurn();
      const wasZoomed = zoomRef.current !== 1;
      resetZoom();
      const target = resolveTurn(currentPageRef.current, direction, pageCount);
      if (target == null) {
        bounce(direction);
        return;
      }
      pendingTurnRef.current = target;
      const slideAway = () => {
        turnFrameRef.current = null;
        setSlideOffset(direction === 'next' ? -containerWidth : containerWidth, true);
        turnTimerRef.current = setTimeout(() => showBookPage(target), TURN_DURATION_MS);
      };
      if (!wasZoomed) {
        slideAway();
        return;
      }
      // A zoomed page shows on its own, so the strip of neighbours only comes back with this
      // render. Let it paint at rest first, or the slide would jump instead of animating.
      setSlideOffset(0, false);
      turnFrameRef.current = requestAnimationFrame(() => {
        turnFrameRef.current = requestAnimationFrame(slideAway);
      });
    },
    [
      isBook,
      pageCount,
      containerWidth,
      finishPendingTurn,
      resetZoom,
      bounce,
      setSlideOffset,
      showBookPage,
    ]
  );

  React.useEffect(() => clearTurnTimer, [clearTurnTimer]);

  // Hardware keys and page-turner pedals turn the page in book mode.
  React.useEffect(() => {
    if (!isBook) return;
    function onKeyDown(e: KeyboardEvent) {
      // A modified arrow belongs to the browser or the host app (Alt+Left is Back, Shift selects).
      if (e.altKey || e.ctrlKey || e.metaKey || e.shiftKey) return;
      const direction = keyTurnFor(e.key);
      if (!direction) return;
      // Keys typed into a text field anywhere on the page are the field's, not a page turn.
      if (isTextEntry(e.target as Element | null) || isTextEntry(document.activeElement)) return;
      e.preventDefault();
      turnPage(direction);
    }
    document.addEventListener('keydown', onKeyDown);
    return () => document.removeEventListener('keydown', onKeyDown);
  }, [isBook, turnPage]);

  // Switching mode keeps the reader's page and starts it at fit.
  React.useLayoutEffect(() => {
    if (!doc) return;
    finishPendingTurn();
    resetZoom();
    if (!isBook) {
      pageContainerRefs.current[currentPageRef.current]?.scrollIntoView({
        behavior: 'instant' as ScrollBehavior,
      });
    }
    // Only a mode switch should move the page; the other dependencies are stable per document.
  }, [isBook]);

  // In book mode, report the page shown when the document opens.
  React.useEffect(() => {
    if (isBook && doc && pageCount > 0) reportPage(currentPageRef.current);
  }, [isBook, doc, pageCount, reportPage]);

  // Go to propPage
  React.useEffect(() => {
    if (propPage == null || !doc) return;
    if (isBook) {
      if (propPage < 0 || propPage >= pageSizes.length) return;
      // `page` is a one-shot command, so acting on it here is the event, not derived state.
      resetZoom();
      // eslint-disable-next-line react-hooks/set-state-in-effect
      showBookPage(propPage);
      return;
    }
    const el = pageContainerRefs.current[propPage];
    el?.scrollIntoView({ behavior: 'instant' as ScrollBehavior });
    // Only a new `page` (or document) is a jump; switching mode keeps the current page instead.
  }, [propPage, doc]);

  // IntersectionObserver → onPageChanged (continuous mode)
  React.useEffect(() => {
    if (isBook || !doc || pageMetas.length === 0) return;
    const els = pageContainerRefs.current.filter(Boolean) as HTMLDivElement[];
    if (els.length === 0) return;
    const io = new IntersectionObserver(
      (entries) => {
        let topPage = -1;
        let topY = Infinity;
        for (const entry of entries) {
          if (entry.isIntersecting) {
            const idx = els.indexOf(entry.target as HTMLDivElement);
            if (idx !== -1 && entry.boundingClientRect.top < topY) {
              topY = entry.boundingClientRect.top;
              topPage = idx;
            }
          }
        }
        if (topPage !== -1) reportPage(topPage);
      },
      { root: scrollContainerRef.current, threshold: 0.1 }
    );
    for (const el of els) io.observe(el);
    return () => io.disconnect();
  }, [isBook, doc, pageMetas, reportPage]);

  // -------------------------------------------------------------------------
  // Book mode gestures: swipes and edge taps
  // -------------------------------------------------------------------------

  function cancelBookGesture() {
    const gesture = gestureRef.current;
    gestureRef.current = null;
    if (gesture?.kind === 'turn' && slideOffsetRef.current !== 0 && turnTimerRef.current == null) {
      setSlideOffset(0, true);
    }
  }

  function handleBookPointerDown(e: React.PointerEvent<HTMLDivElement>) {
    activePointersRef.current.add(e.pointerId);
    if (activePointersRef.current.size > 1) {
      // A second finger means a pinch, never a turn.
      cancelBookGesture();
      return;
    }
    if (e.button !== 0 || annotationMode !== 'none') return;
    const kind = canGestureTurn(displayMode, annotationMode, zoomRef.current) ? 'turn' : 'pan';
    if (kind === 'turn') finishPendingTurn();
    gestureRef.current = {
      startX: e.clientX,
      startY: e.clientY,
      lastX: e.clientX,
      lastY: e.clientY,
      kind,
      moved: false,
    };
    try {
      e.currentTarget.setPointerCapture(e.pointerId);
    } catch {
      // The pointer may already be gone (e.g. a synthetic event); the drag still works without capture.
    }
  }

  function handleBookPointerMove(e: React.PointerEvent<HTMLDivElement>) {
    const gesture = gestureRef.current;
    if (!gesture) return;
    const dx = e.clientX - gesture.startX;
    const dy = e.clientY - gesture.startY;
    if (!gesture.moved && Math.hypot(dx, dy) >= TAP_SLOP_PX) gesture.moved = true;
    if (gesture.kind === 'pan') {
      const el = scrollContainerRef.current;
      if (el) {
        el.scrollLeft -= e.clientX - gesture.lastX;
        el.scrollTop -= e.clientY - gesture.lastY;
      }
    } else if (gesture.moved) {
      // Past either end the page follows the finger only part of the way.
      const blocked = resolveTurn(currentPageRef.current, dx < 0 ? 'next' : 'previous', pageCount);
      setSlideOffset(blocked == null ? dx * EDGE_RESISTANCE : dx, false);
    }
    gesture.lastX = e.clientX;
    gesture.lastY = e.clientY;
  }

  function handleBookPointerUp(e: React.PointerEvent<HTMLDivElement>) {
    activePointersRef.current.delete(e.pointerId);
    const gesture = gestureRef.current;
    gestureRef.current = null;
    if (!gesture || gesture.kind === 'pan') return;
    const dx = e.clientX - gesture.startX;
    const dy = e.clientY - gesture.startY;
    if (!gesture.moved) {
      const rect = e.currentTarget.getBoundingClientRect();
      const direction = classifyTap(e.clientX - rect.left, containerWidth);
      if (direction) turnPage(direction);
      return;
    }
    const direction = classifySwipe(dx, dy, containerWidth);
    if (direction) turnPage(direction);
    else if (slideOffsetRef.current !== 0) setSlideOffset(0, true);
  }

  function handleBookPointerCancel(e: React.PointerEvent<HTMLDivElement>) {
    activePointersRef.current.delete(e.pointerId);
    cancelBookGesture();
  }

  const handleAnnotationAdded = React.useCallback(
    (annotation: Annotation) => {
      applyAnnotations((prev) => [...prev, annotation]);
    },
    [applyAnnotations]
  );

  const handleAnnotationRemoved = React.useCallback(
    (id: string) => {
      applyAnnotations((prev) => prev.filter((a) => a.id !== id));
    },
    [applyAnnotations]
  );

  const handleAnnotationUpdated = React.useCallback(
    (annotation: Annotation) => {
      applyAnnotations((prev) =>
        prev.map((existing) => (existing.id === annotation.id ? annotation : existing))
      );
    },
    [applyAnnotations]
  );

  const handleTextInputRequested = React.useCallback(
    async (request: TextInputRequest, annotation: TextAnnotation | null) => {
      const text = onTextInputRequested
        ? await onTextInputRequested(request)
        : window.prompt(
            request.mode === 'edit' ? 'Edit annotation text:' : 'Enter annotation text:',
            request.currentText ?? ''
          );
      if (!text) return;
      const fontSize = annotation?.fontSize ?? 16;
      const width = text.length * fontSize * 0.6;
      const height = fontSize * 1.5;

      if (annotation) {
        const bounds = {
          x: annotation.bounds.x,
          y: annotation.bounds.y + annotation.bounds.height - height,
          width,
          height,
        };
        applyAnnotations((prev) =>
          prev.map((existing) =>
            existing.id === annotation.id ? { ...annotation, bounds, contents: text } : existing
          )
        );
        return;
      }

      handleAnnotationAdded({
        id: newAnnotationId(),
        type: 'text',
        page: request.page,
        color: annotationColor,
        bounds: {
          x: request.point.x,
          y: request.point.y,
          width,
          height,
        },
        contents: text,
        fontSize,
        fontFamily: annotationFontFamily,
        createdAt: Date.now(),
      });
    },
    [
      annotationColor,
      annotationFontFamily,
      applyAnnotations,
      handleAnnotationAdded,
      onTextInputRequested,
    ]
  );

  const styleObj = style as React.CSSProperties | undefined;

  const pageViewProps = {
    annotations,
    annotationMode,
    annotationColor,
    annotationLineWidth,
    stampText,
    stampSize,
    zoomLevel,
    onAnnotationAdded: handleAnnotationAdded,
    onAnnotationRemoved: handleAnnotationRemoved,
    onAnnotationUpdated: handleAnnotationUpdated,
    onTextInputRequested: handleTextInputRequested,
  };

  const { width, height } = containerSize;
  const zoomed = zoomLevel > 1;
  // Book mode: one slot per page, each the size of the view with the page centred in it. At fit,
  // the current page sits between its neighbours on a strip that slides sideways. Zoomed in,
  // only the current page is shown, and the view scrolls over it.
  const slotStyle: React.CSSProperties = {
    width,
    height,
    flex: 'none',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
  };
  const bookSlots = zoomed ? [currentPage] : [currentPage - 1, currentPage, currentPage + 1];

  // The root element stays the same across modes, so the size and zoom listeners stay attached.
  return (
    <div
      ref={scrollContainerRef}
      data-display-mode={displayMode}
      data-page={isBook ? currentPage : undefined}
      style={
        isBook
          ? {
              overflow: zoomed ? 'auto' : 'hidden',
              backgroundColor,
              height: '100%',
              touchAction: 'none',
              userSelect: 'none',
              ...styleObj,
            }
          : {
              overflowY: 'scroll',
              overflowX: 'auto',
              backgroundColor,
              height: '100%',
              ...styleObj,
            }
      }
      onPointerDown={isBook ? handleBookPointerDown : undefined}
      onPointerMove={isBook ? handleBookPointerMove : undefined}
      onPointerUp={isBook ? handleBookPointerUp : undefined}
      onPointerCancel={isBook ? handleBookPointerCancel : undefined}
    >
      <div style={{ zoom: zoomLevel }}>
        {isBook ? (
          <div
            style={{
              display: 'flex',
              width: width * bookSlots.length,
              transform: zoomed ? undefined : `translateX(${slide.offset - width}px)`,
              transition: slide.animated ? `transform ${TURN_DURATION_MS}ms ease-out` : 'none',
            }}
          >
            {bookSlots.map((i) => (
              <div
                key={i}
                style={slotStyle}
                aria-hidden={i === currentPage ? undefined : true}
                data-book-slot={i}
              >
                {doc && pageMetas[i] && (
                  <PageView
                    {...pageViewProps}
                    doc={doc}
                    pageIndex={i}
                    meta={pageMetas[i]}
                    containerRef={(el) => {
                      pageContainerRefs.current[i] = el;
                    }}
                  />
                )}
              </div>
            ))}
          </div>
        ) : (
          doc &&
          pageMetas.map((meta, i) => (
            <React.Fragment key={i}>
              <PageView
                {...pageViewProps}
                doc={doc}
                pageIndex={i}
                meta={meta}
                containerRef={(el) => {
                  pageContainerRefs.current[i] = el;
                }}
              />
              {i < pageMetas.length - 1 && <div style={{ height: 8 }} aria-hidden />}
            </React.Fragment>
          ))
        )}
      </div>
    </div>
  );
}
