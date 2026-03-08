package dev.terhoeven.expopdfmarkup

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.pdf.PdfRenderer
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.view.View
import android.widget.OverScroller
import java.util.UUID

class ContinuousPdfView(context: Context) : View(context) {
    private val pageBitmaps = mutableListOf<Bitmap>()
    private val pageYOffsets = mutableListOf<Float>()
    private val pageWidths = mutableListOf<Int>()
    private val pageHeights = mutableListOf<Int>()
    private val renderScales = mutableListOf<Float>()
    private var totalHeight = 0f
    private var contentWidth = 0f
    private val pageGap = (8 * resources.displayMetrics.density).toInt()
    var pageBackgroundColor = Color.rgb(235, 235, 235)

    private var currentScale = 1f
    private var minScale = 1f
    private var maxScale = 5f
    private var panX = 0f
    private var panY = 0f

    private var lastNotifiedPage = -1

    private val scroller = OverScroller(context)
    private val scaleDetector = ScaleGestureDetector(context, ScaleListener())
    private val gestureDetector = GestureDetector(context, GestureListener())

    var onPageChangeListener: ((page: Int, pageCount: Int) -> Unit)? = null

    // Annotation state
    var annotations: List<AnnotationModel> = emptyList()
        set(value) {
            field = value
            invalidate()
        }
    var annotationMode: String = "none"
    var annotationColor: String = "#000000"
    var annotationLineWidth: Float = 2f
    var onAnnotationsChangedListener: (() -> Unit)? = null

    // Ink drawing state
    private var currentInkPoints = mutableListOf<AnnotationPoint>()
    private var isDrawingInk = false
    private var inkScreenPath = Path()

    // Highlight/underline drag state
    private var dragStartPoint: AnnotationPoint? = null
    private var dragCurrentPoint: AnnotationPoint? = null
    private var isDragging = false

    // Text mode callback
    var onTextInputRequested: ((page: Int, point: AnnotationPoint) -> Unit)? = null

    fun loadPages(renderer: PdfRenderer, viewWidth: Int) {
        recycle()
        if (viewWidth <= 0) return
        setBackgroundColor(pageBackgroundColor)

        var yOffset = 0f
        for (i in 0 until renderer.pageCount) {
            if (i > 0) yOffset += pageGap

            val page = renderer.openPage(i)
            val pdfW = page.width
            val pdfH = page.height
            val scale = viewWidth.toFloat() / pdfW.toFloat()
            val bmpH = (pdfH * scale).toInt()

            val bmp = Bitmap.createBitmap(viewWidth, bmpH, Bitmap.Config.ARGB_8888)
            Canvas(bmp).drawColor(Color.WHITE)

            val m = Matrix()
            m.setScale(scale, scale)
            page.render(bmp, null, m, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
            page.close()

            pageYOffsets.add(yOffset)
            pageBitmaps.add(bmp)
            pageWidths.add(pdfW)
            pageHeights.add(pdfH)
            renderScales.add(scale)
            yOffset += bmpH
        }

        totalHeight = yOffset
        contentWidth = viewWidth.toFloat()
        currentScale = 1f
        minScale = 1f
        maxScale = 5f
        panX = 0f
        panY = 0f
        lastNotifiedPage = -1
        invalidate()
        notifyPageChange()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (pageBitmaps.isEmpty()) return

        canvas.save()
        canvas.translate(-panX, -panY)
        canvas.scale(currentScale, currentScale)

        for (i in pageBitmaps.indices) {
            val pageTop = pageYOffsets[i] * currentScale
            val pageBottom = pageTop + pageBitmaps[i].height * currentScale
            val visibleTop = panY
            val visibleBottom = panY + height

            // Only draw pages that are visible
            if (pageBottom >= visibleTop && pageTop <= visibleBottom) {
                canvas.drawBitmap(pageBitmaps[i], 0f, pageYOffsets[i], null)
                AnnotationRenderer.drawAnnotations(
                    canvas,
                    annotations,
                    i,
                    pageYOffsets[i],
                    renderScales[i],
                    pageHeights[i]
                )
            }
        }

        canvas.restore()

        // Draw live ink preview (in screen coordinates)
        if (isDrawingInk && currentInkPoints.size > 1) {
            val paint = Paint().apply {
                color = AnnotationSerializer.colorFromHex(annotationColor)
                strokeWidth = annotationLineWidth * currentScale
                style = Paint.Style.STROKE
                isAntiAlias = true
                strokeCap = Paint.Cap.ROUND
                strokeJoin = Paint.Join.ROUND
            }
            canvas.drawPath(inkScreenPath, paint)
        }

        // Draw drag preview for highlight/underline
        if (isDragging && dragStartPoint != null && dragCurrentPoint != null) {
            val startSP = dragStartPoint!!
            val curSP = dragCurrentPoint!!
            val paint = Paint().apply {
                color = AnnotationSerializer.colorFromHex(annotationColor)
                alpha = if (annotationMode == "highlight") 80 else 255
                style = if (annotationMode == "highlight") Paint.Style.FILL else Paint.Style.STROKE
                strokeWidth = if (annotationMode == "underline") 1f * currentScale else 0f
                isAntiAlias = true
            }
            val left = minOf(startSP.x, curSP.x)
            val top = minOf(startSP.y, curSP.y)
            val right = maxOf(startSP.x, curSP.x)
            val bottom = maxOf(startSP.y, curSP.y)
            if (annotationMode == "underline") {
                canvas.drawLine(left, bottom, right, bottom, paint)
            } else {
                canvas.drawRect(left, top, right, bottom, paint)
            }
        }
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        // Always let scale detector handle pinch zoom
        scaleDetector.onTouchEvent(event)

        // If scaling with two fingers, don't process as annotation gesture
        if (scaleDetector.isInProgress) return true

        when (annotationMode) {
            "ink" -> {
                if (event.pointerCount == 1) {
                    handleInkTouch(event)
                    return true
                }
            }

            "highlight", "underline" -> {
                if (event.pointerCount == 1) {
                    handleDragTouch(event)
                    return true
                }
            }

            "eraser" -> {
                if (event.action == MotionEvent.ACTION_UP && event.pointerCount == 1) {
                    handleEraserTap(event)
                }
                gestureDetector.onTouchEvent(event)
                return true
            }

            "text" -> {
                if (event.action == MotionEvent.ACTION_UP && event.pointerCount == 1) {
                    handleTextTap(event)
                }
                gestureDetector.onTouchEvent(event)
                return true
            }

            else -> {
                // "none" mode — normal scroll/zoom
                gestureDetector.onTouchEvent(event)
            }
        }

        parent?.requestDisallowInterceptTouchEvent(true)
        return true
    }

    // --- Ink mode ---

    private fun handleInkTouch(event: MotionEvent) {
        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                isDrawingInk = true
                currentInkPoints.clear()
                inkScreenPath.reset()
                val pt = AnnotationPoint(event.x, event.y)
                currentInkPoints.add(pt)
                inkScreenPath.moveTo(event.x, event.y)
                parent?.requestDisallowInterceptTouchEvent(true)
            }

            MotionEvent.ACTION_MOVE -> {
                if (isDrawingInk) {
                    val pt = AnnotationPoint(event.x, event.y)
                    currentInkPoints.add(pt)
                    inkScreenPath.lineTo(event.x, event.y)
                    invalidate()
                }
            }

            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                if (isDrawingInk && currentInkPoints.size >= 1) {
                    finishInkStroke()
                }
                isDrawingInk = false
                inkScreenPath.reset()
                invalidate()
            }
        }
    }

    private fun finishInkStroke() {
        // Convert screen points to PDF page coordinates
        val pdfPoints = mutableListOf<AnnotationPoint>()
        var pageIndex = -1

        for (screenPt in currentInkPoints) {
            val contentX = (screenPt.x + panX) / currentScale
            val contentY = (screenPt.y + panY) / currentScale
            val pi = pageIndexAtContentY(contentY)
            if (pageIndex == -1) pageIndex = pi
            if (pi != pageIndex || pi < 0) continue

            val localY = contentY - pageYOffsets[pi]
            val pdfX = contentX / renderScales[pi]
            val pdfY = pageHeights[pi] - (localY / renderScales[pi])
            pdfPoints.add(AnnotationPoint(pdfX, pdfY))
        }

        if (pdfPoints.isEmpty() || pageIndex < 0) return

        val annotation = AnnotationModel(
            id = UUID.randomUUID().toString(),
            type = "ink",
            page = pageIndex,
            color = annotationColor,
            lineWidth = annotationLineWidth,
            paths = listOf(pdfPoints),
            createdAt = System.currentTimeMillis() / 1000.0
        )
        annotations = annotations + annotation
        onAnnotationsChangedListener?.invoke()
    }

    // --- Highlight/Underline drag mode ---

    private fun handleDragTouch(event: MotionEvent) {
        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                isDragging = true
                dragStartPoint = AnnotationPoint(event.x, event.y)
                dragCurrentPoint = dragStartPoint
                parent?.requestDisallowInterceptTouchEvent(true)
            }

            MotionEvent.ACTION_MOVE -> {
                if (isDragging) {
                    dragCurrentPoint = AnnotationPoint(event.x, event.y)
                    invalidate()
                }
            }

            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                if (isDragging && dragStartPoint != null && dragCurrentPoint != null) {
                    finishDragAnnotation()
                }
                isDragging = false
                dragStartPoint = null
                dragCurrentPoint = null
                invalidate()
            }
        }
    }

    private fun finishDragAnnotation() {
        val start = dragStartPoint ?: return
        val end = dragCurrentPoint ?: return

        // Convert screen points to content space
        val startCX = (start.x + panX) / currentScale
        val startCY = (start.y + panY) / currentScale
        val endCX = (end.x + panX) / currentScale
        val endCY = (end.y + panY) / currentScale

        val pageIndex = pageIndexAtContentY(startCY)
        if (pageIndex < 0) return

        val rs = renderScales[pageIndex]
        val ph = pageHeights[pageIndex]
        val localStartY = startCY - pageYOffsets[pageIndex]
        val localEndY = endCY - pageYOffsets[pageIndex]

        // Convert to PDF coordinates
        val pdfX1 = startCX / rs
        val pdfY1 = ph - (localStartY / rs)
        val pdfX2 = endCX / rs
        val pdfY2 = ph - (localEndY / rs)

        val left = minOf(pdfX1, pdfX2)
        val right = maxOf(pdfX1, pdfX2)
        val bottom = minOf(pdfY1, pdfY2)
        val top = maxOf(pdfY1, pdfY2)
        val w = right - left
        val h = top - bottom

        if (w < 2f && h < 2f) return // too small

        val annotation = AnnotationModel(
            id = UUID.randomUUID().toString(),
            type = annotationMode,
            page = pageIndex,
            color = annotationColor,
            alpha = if (annotationMode == "highlight") 0.5f else null,
            bounds = AnnotationBounds(left, bottom, w, h),
            createdAt = System.currentTimeMillis() / 1000.0
        )
        annotations = annotations + annotation
        onAnnotationsChangedListener?.invoke()
    }

    // --- Eraser mode ---

    private fun handleEraserTap(event: MotionEvent) {
        val contentX = (event.x + panX) / currentScale
        val contentY = (event.y + panY) / currentScale
        val pageIndex = pageIndexAtContentY(contentY)
        if (pageIndex < 0) return

        val localY = contentY - pageYOffsets[pageIndex]
        val pdfX = contentX / renderScales[pageIndex]
        val pdfY = pageHeights[pageIndex] - (localY / renderScales[pageIndex])

        val hit = AnnotationHitTester.hitTest(
            AnnotationPoint(pdfX, pdfY),
            annotations,
            pageIndex
        )
        if (hit != null) {
            annotations = annotations.filter { it.id != hit.id }
            onAnnotationsChangedListener?.invoke()
        }
    }

    // --- Text mode ---

    private fun handleTextTap(event: MotionEvent) {
        val contentX = (event.x + panX) / currentScale
        val contentY = (event.y + panY) / currentScale
        val pageIndex = pageIndexAtContentY(contentY)
        if (pageIndex < 0) return

        val localY = contentY - pageYOffsets[pageIndex]
        val pdfX = contentX / renderScales[pageIndex]
        val pdfY = pageHeights[pageIndex] - (localY / renderScales[pageIndex])

        onTextInputRequested?.invoke(pageIndex, AnnotationPoint(pdfX, pdfY))
    }

    fun addTextAnnotation(page: Int, point: AnnotationPoint, text: String) {
        val fontSize = 16f
        val paint = Paint().apply { textSize = fontSize }
        val textWidth = paint.measureText(text)
        val annotation = AnnotationModel(
            id = UUID.randomUUID().toString(),
            type = "freeText",
            page = page,
            color = annotationColor,
            bounds = AnnotationBounds(point.x, point.y - fontSize, textWidth, fontSize * 1.2f),
            contents = text,
            fontSize = fontSize,
            createdAt = System.currentTimeMillis() / 1000.0
        )
        annotations = annotations + annotation
        onAnnotationsChangedListener?.invoke()
    }

    // --- Helpers ---

    private fun pageIndexAtContentY(contentY: Float): Int {
        for (i in pageYOffsets.indices.reversed()) {
            if (pageYOffsets[i] <= contentY) return i
        }
        return 0
    }

    override fun computeScroll() {
        if (scroller.computeScrollOffset()) {
            panX = scroller.currX.toFloat()
            panY = scroller.currY.toFloat()
            constrainPan()
            invalidate()
            notifyPageChange()
        }
    }

    private fun constrainPan() {
        val maxX = maxOf(0f, contentWidth * currentScale - width)
        val maxY = maxOf(0f, totalHeight * currentScale - height)
        panX = panX.coerceIn(0f, maxX)
        panY = panY.coerceIn(0f, maxY)
    }

    private fun getVisiblePage(): Int {
        val centerY = (panY + height / 2f) / currentScale
        for (i in pageYOffsets.indices.reversed()) {
            if (pageYOffsets[i] <= centerY) return i
        }
        return 0
    }

    fun scrollToPage(pageIndex: Int) {
        if (pageIndex < 0 || pageIndex >= pageYOffsets.size) return
        panY = pageYOffsets[pageIndex] * currentScale
        constrainPan()
        invalidate()
        notifyPageChange()
    }

    private fun notifyPageChange() {
        val page = getVisiblePage()
        if (page != lastNotifiedPage) {
            lastNotifiedPage = page
            onPageChangeListener?.invoke(page, pageBitmaps.size)
        }
    }

    fun recycle() {
        pageBitmaps.forEach { it.recycle() }
        pageBitmaps.clear()
        pageYOffsets.clear()
        pageWidths.clear()
        pageHeights.clear()
        renderScales.clear()
        totalHeight = 0f
        lastNotifiedPage = -1
    }

    private inner class ScaleListener : ScaleGestureDetector.SimpleOnScaleGestureListener() {
        override fun onScale(detector: ScaleGestureDetector): Boolean {
            val oldScale = currentScale
            currentScale = (currentScale * detector.scaleFactor).coerceIn(minScale, maxScale)
            val ratio = currentScale / oldScale
            panX = (panX + detector.focusX) * ratio - detector.focusX
            panY = (panY + detector.focusY) * ratio - detector.focusY
            constrainPan()
            invalidate()
            return true
        }

        override fun onScaleBegin(detector: ScaleGestureDetector): Boolean = true
    }

    private inner class GestureListener : GestureDetector.SimpleOnGestureListener() {
        override fun onDown(e: MotionEvent): Boolean = true

        override fun onScroll(e1: MotionEvent?, e2: MotionEvent, dx: Float, dy: Float): Boolean {
            panX += dx
            panY += dy
            constrainPan()
            invalidate()
            notifyPageChange()
            return true
        }

        override fun onFling(e1: MotionEvent?, e2: MotionEvent, vx: Float, vy: Float): Boolean {
            scroller.fling(
                panX.toInt(),
                panY.toInt(),
                -vx.toInt(),
                -vy.toInt(),
                0,
                maxOf(0, (contentWidth * currentScale - width).toInt()),
                0,
                maxOf(0, (totalHeight * currentScale - height).toInt())
            )
            invalidate()
            return true
        }

        override fun onDoubleTap(e: MotionEvent): Boolean {
            val targetScale = if (currentScale > minScale * 1.5f) minScale else minScale * 2.5f
            val oldScale = currentScale
            currentScale = targetScale
            val ratio = currentScale / oldScale
            panX = (panX + e.x) * ratio - e.x
            panY = (panY + e.y) * ratio - e.y
            constrainPan()
            invalidate()
            notifyPageChange()
            return true
        }
    }
}
