import * as pdfjs from 'pdfjs-dist';
import type { PDFDocumentProxy, PDFPageProxy } from 'pdfjs-dist';
import * as React from 'react';

import type {
  Annotation,
  AnnotationMode,
  AnnotationPoint,
  ExpoPdfMarkupViewProps,
} from './ExpoPdfMarkup.types';
import {
  canvasRectToPdfBounds,
  canvasToPdf,
  drawAnnotationsOnCanvas,
  hitTestAnnotation,
  newAnnotationId,
  parseAnnotations,
  serializeAnnotations,
} from './web/annotationUtils';
import type { PdfPageMeta } from './web/types';

// Configure pdfjs worker once at module level (consumers can override before mounting)
if (!pdfjs.GlobalWorkerOptions.workerSrc) {
  // Default: served from public/ by withPdfMarkup() in metro.js.
  // Override with setPdfJsWorkerSrc() if using a different bundler or CDN.
  pdfjs.GlobalWorkerOptions.workerSrc = '/pdf.worker.min.mjs';
}

/** Allow consumers to override the pdfjs worker URL before mounting the view. */
export function setPdfJsWorkerSrc(url: string): void {
  pdfjs.GlobalWorkerOptions.workerSrc = url;
}

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
  onAnnotationAdded: (annotation: Annotation) => void;
  onAnnotationRemoved: (id: string) => void;
  onTextInputRequested: (pageIndex: number, pdfPoint: AnnotationPoint) => void;
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
  onAnnotationAdded,
  onAnnotationRemoved,
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

  const dpr = typeof window !== 'undefined' ? window.devicePixelRatio ?? 1 : 1;
  const cssWidth = meta.canvasWidth / dpr;
  const cssHeight = meta.canvasHeight / dpr;

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
      const task = page.render({ canvasContext: ctx, viewport });
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
      drawAnnotationsOnCanvas(ctx, annotations, pageIndex, meta);
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
    [annotations, pageIndex, meta, dpr, annotationColor, annotationLineWidth]
  );

  React.useEffect(() => {
    redrawAnnotations();
  }, [redrawAnnotations]);

  function getCanvasPoint(e: React.PointerEvent<HTMLCanvasElement>): { x: number; y: number } {
    const rect = (e.currentTarget as HTMLCanvasElement).getBoundingClientRect();
    return { x: e.clientX - rect.left, y: e.clientY - rect.top };
  }

  function handlePointerDown(e: React.PointerEvent<HTMLCanvasElement>) {
    if (annotationMode === 'none') return;
    e.currentTarget.setPointerCapture(e.pointerId);
    const pt = getCanvasPoint(e);
    pointerDownRef.current = true;
    if (annotationMode === 'ink') {
      inkPointsRef.current = [pt];
    } else if (annotationMode === 'highlight' || annotationMode === 'underline') {
      dragStartRef.current = pt;
      dragCurrentRef.current = pt;
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
    }
  }

  function handlePointerUp(e: React.PointerEvent<HTMLCanvasElement>) {
    if (!pointerDownRef.current && annotationMode !== 'text' && annotationMode !== 'eraser') return;
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
    } else if (annotationMode === 'text') {
      const pdfPoint = canvasToPdf(pt.x, pt.y, scale, pdfHeight);
      onTextInputRequested(pageIndex, pdfPoint);
    } else if (annotationMode === 'eraser') {
      const pdfPoint = canvasToPdf(pt.x, pt.y, scale, pdfHeight);
      const hit = hitTestAnnotation(pdfPoint, annotations, pageIndex);
      if (hit) onAnnotationRemoved(hit.id);
    }
  }

  const pointerEvents = annotationMode === 'none' ? 'none' : 'auto';

  return (
    <div
      ref={containerRef}
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
          cursor: 'crosshair',
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

export default function ExpoPdfMarkupView(props: ExpoPdfMarkupViewProps) {
  const {
    source,
    page: propPage,
    backgroundColor = '#f0f0f0',
    annotations: annotationsProp,
    annotationMode = 'none',
    annotationColor = '#FF0000',
    annotationLineWidth = 2,
    onPageChanged,
    onLoadComplete,
    onError,
    onAnnotationsChanged,
    style,
  } = props;

  const scrollContainerRef = React.useRef<HTMLDivElement>(null);
  const [containerWidth, setContainerWidth] = React.useState(0);
  const [doc, setDoc] = React.useState<PDFDocumentProxy | null>(null);
  const [pageMetas, setPageMetas] = React.useState<PdfPageMeta[]>([]);
  const [annotations, setAnnotations] = React.useState<Annotation[]>([]);
  const lastAnnotationsJsonRef = React.useRef<string | undefined>(undefined);
  const pageContainerRefs = React.useRef<(HTMLDivElement | null)[]>([]);
  const docRef = React.useRef<PDFDocumentProxy | null>(null);
  const loadingSourceRef = React.useRef<string | null>(null);

  // ResizeObserver → containerWidth
  React.useEffect(() => {
    const el = scrollContainerRef.current;
    if (!el) return;
    const ro = new ResizeObserver((entries) => {
      const width = entries[0]?.contentRect.width ?? 0;
      setContainerWidth(width);
    });
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  // Load PDF when source or containerWidth changes
  React.useEffect(() => {
    if (!source || containerWidth <= 0) return;
    let cancelled = false;
    loadingSourceRef.current = source;

    async function load() {
      try {
        const task = pdfjs.getDocument(source);
        const loadedDoc = await task.promise;
        if (cancelled || loadingSourceRef.current !== source) {
          loadedDoc.destroy();
          return;
        }
        const metas: PdfPageMeta[] = [];
        const dpr = window.devicePixelRatio ?? 1;
        for (let i = 1; i <= loadedDoc.numPages; i++) {
          const pg = await loadedDoc.getPage(i);
          if (cancelled) {
            pg.cleanup();
            loadedDoc.destroy();
            return;
          }
          const viewport = pg.getViewport({ scale: 1 });
          const scale = containerWidth / viewport.width;
          const cssHeight = viewport.height * scale;
          metas.push({
            pdfWidth: viewport.width,
            pdfHeight: viewport.height,
            scale,
            canvasWidth: Math.round(containerWidth * dpr),
            canvasHeight: Math.round(cssHeight * dpr),
          });
          pg.cleanup();
        }
        docRef.current?.destroy();
        docRef.current = loadedDoc;
        setDoc(loadedDoc);
        setPageMetas(metas);
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
  }, [source, containerWidth]); // intentionally omit callbacks — they should not re-trigger a PDF load

  // Sync annotations prop → state (guard round-trips)
  React.useEffect(() => {
    if (annotationsProp === lastAnnotationsJsonRef.current) return;
    lastAnnotationsJsonRef.current = annotationsProp;
    const parsed = parseAnnotations(annotationsProp);
    setAnnotations(parsed.annotations);
  }, [annotationsProp]);

  // Scroll to propPage
  React.useEffect(() => {
    if (propPage == null || !doc) return;
    const el = pageContainerRefs.current[propPage];
    el?.scrollIntoView({ behavior: 'instant' as ScrollBehavior });
  }, [propPage, doc]);

  // IntersectionObserver → onPageChanged
  React.useEffect(() => {
    if (!doc || pageMetas.length === 0) return;
    const els = pageContainerRefs.current.filter(Boolean) as HTMLDivElement[];
    if (els.length === 0) return;
    let lastReported = -1;
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
        if (topPage !== -1 && topPage !== lastReported) {
          lastReported = topPage;
          onPageChanged?.({ nativeEvent: { page: topPage, pageCount: doc.numPages } });
        }
      },
      { root: scrollContainerRef.current, threshold: 0.1 }
    );
    for (const el of els) io.observe(el);
    return () => io.disconnect();
  }, [doc, pageMetas, onPageChanged]);

  const handleAnnotationAdded = React.useCallback(
    (annotation: Annotation) => {
      setAnnotations((prev) => {
        const next = [...prev, annotation];
        const json = serializeAnnotations({ version: 1, annotations: next });
        lastAnnotationsJsonRef.current = json;
        onAnnotationsChanged?.({ nativeEvent: { annotations: json } });
        return next;
      });
    },
    [onAnnotationsChanged]
  );

  const handleAnnotationRemoved = React.useCallback(
    (id: string) => {
      setAnnotations((prev) => {
        const next = prev.filter((a) => a.id !== id);
        const json = serializeAnnotations({ version: 1, annotations: next });
        lastAnnotationsJsonRef.current = json;
        onAnnotationsChanged?.({ nativeEvent: { annotations: json } });
        return next;
      });
    },
    [onAnnotationsChanged]
  );

  const handleTextInputRequested = React.useCallback(
    (pageIndex: number, pdfPoint: AnnotationPoint) => {
      const text = window.prompt('Enter annotation text:');
      if (!text) return;
      const fontSize = 16;
      const estimatedWidth = text.length * fontSize * 0.6;
      const bounds = {
        x: pdfPoint.x,
        y: pdfPoint.y,
        width: estimatedWidth,
        height: fontSize * 1.5,
      };
      handleAnnotationAdded({
        id: newAnnotationId(),
        type: 'text',
        page: pageIndex,
        color: annotationColor,
        bounds,
        contents: text,
        fontSize,
        createdAt: Date.now(),
      });
    },
    [annotationColor, handleAnnotationAdded]
  );

  const styleObj = style as React.CSSProperties | undefined;

  return (
    <div
      ref={scrollContainerRef}
      style={{
        overflowY: 'scroll',
        backgroundColor,
        height: '100%',
        ...styleObj,
      }}
    >
      {doc &&
        pageMetas.map((meta, i) => (
          <React.Fragment key={i}>
            <div style={{ height: 8 }} aria-hidden />
            <PageView
              doc={doc}
              pageIndex={i}
              meta={meta}
              annotations={annotations}
              annotationMode={annotationMode}
              annotationColor={annotationColor}
              annotationLineWidth={annotationLineWidth}
              onAnnotationAdded={handleAnnotationAdded}
              onAnnotationRemoved={handleAnnotationRemoved}
              onTextInputRequested={handleTextInputRequested}
              containerRef={(el) => {
                pageContainerRefs.current[i] = el;
              }}
            />
          </React.Fragment>
        ))}
    </div>
  );
}
