package dev.terhoeven.expopdfmarkup

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
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
import android.view.animation.DecelerateInterpolator
import android.widget.OverScroller
import java.util.UUID

/**
 * Draws the PDF and handles touches in both display modes:
 * - continuous: every page stacked in one vertical scroll (the default).
 * - book ([isBookMode]): one page at a time, fitted to the view, turned
 *   sideways. All pages share one content slot; only [BookPager.currentPage]
 *   (plus its neighbour while sliding) is drawn. Swipe-or-pan and edge-tap
 *   decisions come from [BookTurnPolicy]; every turn goes through [turnPage].
 */
class ContinuousPdfView(context: Context) : View(context) {
    data class ScrollState(val panX: Float, val panY: Float, val scale: Float, val page: Int)

    var pendingScrollRestore: ScrollState? = null

    fun captureScrollState(): ScrollState? {
        if (pageBitmaps.isEmpty()) return null
        return ScrollState(panX, panY, currentScale, currentPage)
    }

    /** Book mode lays pages out one at a time. Set before [loadPages]. */
    var isBookMode = false

    /** The page in view: the one shown in book mode, the one at mid-height in continuous. */
    val currentPage: Int get() = getVisiblePage()

    private val bookPager = BookPager { notifyPageChange() }
    private val density = resources.displayMetrics.density

    /** Screen-space horizontal offset of the shown page while dragging or sliding. */
    private var slideOffset = 0f

    /** The page drawn beside the shown page while dragging or sliding, or -1. */
    private var slideNeighbour = -1
    private var slideAnimator: ValueAnimator? = null
    private var bookSwipeAction = BookTurnPolicy.SwipeAction.PAN
    private var bookSwipeDownX = 0f
    private var isBookSwiping = false
    private var bookSwipeVelocityX = 0f

    private val pageBitmaps = mutableListOf<Bitmap>()
    private val pageXOffsets = mutableListOf<Float>()
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

    var onPageChangeListener: (
        (page: Int, pageCount: Int, pageWidth: Int, pageHeight: Int) -> Unit
    )? = null

    // Annotation state
    var annotations: List<AnnotationModel> = emptyList()
        set(value) {
            field = value
            invalidate()
        }
    var annotationMode: String = "none"
        set(value) {
            if (field == value) return
            field = value
            if (value != "ink") {
                isDrawingInk = false
                currentInkPoints.clear()
                inkScreenPath.reset()
            }
            if (value != "highlight" && value != "underline") {
                isDragging = false
                dragStartPoint = null
                dragCurrentPoint = null
            }
            if (value != "move") {
                clearMovePreview()
            }
            invalidate()
        }
    var annotationColor: String = "#000000"
    var annotationLineWidth: Float = 2f
    var annotationFontFamily: String? = null
    var stampText: String? = null
    var stampSize: Float = 48f
    var onAnnotationsChangedListener: (() -> Unit)? = null

    // Ink drawing state
    private var currentInkPoints = mutableListOf<AnnotationPoint>()
    private var isDrawingInk = false
    private var inkScreenPath = Path()

    // Highlight/underline drag state
    private var dragStartPoint: AnnotationPoint? = null
    private var dragCurrentPoint: AnnotationPoint? = null
    private var isDragging = false

    // Move mode state
    private var movingAnnotation: AnnotationModel? = null
    private var movingPreviewAnnotation: AnnotationModel? = null
    private var moveStartPdfPoint: AnnotationPoint? = null

    // Text mode callback
    var onTextInputRequested: (
        (page: Int, point: AnnotationPoint, annotation: AnnotationModel?) -> Unit
    )? = null

    /**
     * Renders every page for the current display mode. With [startPage] (a
     * mode switch, rotation or resize) the view stays on that page and does
     * not report it again; without it the view starts at the top.
     */
    fun loadPages(renderer: PdfRenderer, viewWidth: Int, viewHeight: Int, startPage: Int? = null) {
        val keptNotifiedPage = lastNotifiedPage
        recycle()
        if (viewWidth <= 0 || (isBookMode && viewHeight <= 0)) return
        setBackgroundColor(pageBackgroundColor)

        var yOffset = 0f
        for (i in 0 until renderer.pageCount) {
            if (!isBookMode && i > 0) yOffset += pageGap

            val page = renderer.openPage(i)
            val pdfW = page.width
            val pdfH = page.height
            val scale = if (isBookMode) {
                minOf(viewWidth.toFloat() / pdfW, viewHeight.toFloat() / pdfH)
            } else {
                viewWidth.toFloat() / pdfW.toFloat()
            }
            val bmpW = if (isBookMode) maxOf(1, (pdfW * scale).toInt()) else viewWidth
            val bmpH = if (isBookMode) maxOf(1, (pdfH * scale).toInt()) else (pdfH * scale).toInt()

            val bmp = Bitmap.createBitmap(bmpW, bmpH, Bitmap.Config.ARGB_8888)
            Canvas(bmp).drawColor(Color.WHITE)

            val m = Matrix()
            m.setScale(scale, scale)
            page.render(bmp, null, m, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
            page.close()

            if (isBookMode) {
                // Every page sits centred in the same view-sized slot.
                pageXOffsets.add((viewWidth - bmpW) / 2f)
                pageYOffsets.add((viewHeight - bmpH) / 2f)
            } else {
                pageXOffsets.add(0f)
                pageYOffsets.add(yOffset)
                yOffset += bmpH
            }
            pageBitmaps.add(bmp)
            pageWidths.add(pdfW)
            pageHeights.add(pdfH)
            renderScales.add(scale)
        }

        totalHeight = if (isBookMode) viewHeight.toFloat() else yOffset
        contentWidth = viewWidth.toFloat()
        currentScale = 1f
        minScale = 1f
        maxScale = 5f
        panX = 0f
        panY = 0f
        lastNotifiedPage = if (startPage != null) keptNotifiedPage else -1
        bookPager.reset(renderer.pageCount, startPage ?: 0)

        if (startPage != null && !isBookMode && startPage in pageYOffsets.indices) {
            panY = pageYOffsets[startPage]
            constrainPan()
        }

        pendingScrollRestore?.let { state ->
            if (isBookMode) {
                bookPager.reset(renderer.pageCount, state.page)
            } else {
                currentScale = state.scale.coerceIn(minScale, maxScale)
                panX = state.panX
                panY = state.panY
                constrainPan()
            }
            pendingScrollRestore = null
        }

        invalidate()
        notifyPageChange()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (pageBitmaps.isEmpty()) return

        val renderedAnnotations =
            if (movingAnnotation != null && movingPreviewAnnotation != null) {
                annotations.map { annotation ->
                    if (annotation.id ==
                        movingAnnotation!!.id
                    ) {
                        movingPreviewAnnotation!!
                    } else {
                        annotation
                    }
                }
            } else {
                annotations
            }

        if (isBookMode) {
            drawBookPages(canvas, renderedAnnotations)
        } else {
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
                    drawPage(canvas, i, renderedAnnotations)
                }
            }

            canvas.restore()
        }

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

    /** Draws page [i] and its markup in content space, at its layout offset. */
    private fun drawPage(canvas: Canvas, i: Int, renderedAnnotations: List<AnnotationModel>) {
        canvas.save()
        canvas.translate(pageXOffsets[i], 0f)
        canvas.drawBitmap(pageBitmaps[i], 0f, pageYOffsets[i], null)
        AnnotationRenderer.drawAnnotations(
            canvas,
            renderedAnnotations,
            i,
            pageYOffsets[i],
            renderScales[i],
            pageHeights[i],
            context
        )
        if (annotationMode == "move" || annotationMode == "eraser") {
            AnnotationRenderer.drawEditingAffordances(
                canvas,
                renderedAnnotations,
                i,
                pageYOffsets[i],
                renderScales[i],
                pageHeights[i],
                currentScale
            )
        }
        canvas.restore()
    }

    /** Book mode: the shown page, plus its neighbour beside it while sliding. */
    private fun drawBookPages(canvas: Canvas, renderedAnnotations: List<AnnotationModel>) {
        val shown = bookPager.currentPage
        if (shown !in pageBitmaps.indices) return

        canvas.save()
        canvas.translate(slideOffset - panX, -panY)
        canvas.scale(currentScale, currentScale)
        drawPage(canvas, shown, renderedAnnotations)
        canvas.restore()

        if (slideNeighbour in pageBitmaps.indices && slideNeighbour != shown) {
            // The next page waits off the right edge, the previous off the left.
            val side = if (slideNeighbour > shown) 1f else -1f
            canvas.save()
            canvas.translate(slideOffset + side * width, 0f)
            drawPage(canvas, slideNeighbour, renderedAnnotations)
            canvas.restore()
        }
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        // Hold off parent interception (e.g. gesture-handler root, scroll
        // containers) for the duration of each gesture only; leaving it set
        // permanently can strand ancestors shared with sibling screens.
        TouchInterceptPolicy.disallowInterceptFor(event.actionMasked)?.let {
            parent?.requestDisallowInterceptTouchEvent(it)
        }

        // A new touch in book mode lands any slide still running, so markup
        // and taps always act on the page that is fully in view.
        if (isBookMode && event.actionMasked == MotionEvent.ACTION_DOWN) {
            slideAnimator?.end()
        }

        // Always let scale detector handle pinch zoom
        scaleDetector.onTouchEvent(event)

        // If scaling with two fingers, don't process as annotation gesture
        if (scaleDetector.isInProgress) {
            if (isBookSwiping) settleBookSwipe()
            return true
        }

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

            "move" -> {
                if (event.pointerCount == 1) {
                    handleMoveTouch(event)
                    return true
                }
            }

            "text" -> {
                if (event.action == MotionEvent.ACTION_UP && event.pointerCount == 1) {
                    handleTextTap(event)
                }
                gestureDetector.onTouchEvent(event)
                return true
            }

            "stamp" -> {
                if (event.action == MotionEvent.ACTION_UP && event.pointerCount == 1) {
                    handleStampTap(event)
                }
                gestureDetector.onTouchEvent(event)
                return true
            }

            else -> {
                // "none" mode — normal scroll/zoom (book mode: swipe turns at fit)
                gestureDetector.onTouchEvent(event)
                if (isBookMode) {
                    val action = event.actionMasked
                    if (action == MotionEvent.ACTION_UP) releaseBookSwipe()
                    if (action == MotionEvent.ACTION_CANCEL) settleBookSwipe()
                }
            }
        }

        return true
    }

    /**
     * Cancels any in-progress gesture (ink stroke, drag, move, fling) and
     * releases the parent touch-intercept hold. Needed when the gesture is
     * interrupted without a final ACTION_UP/ACTION_CANCEL — device lock
     * (window focus loss) or view teardown — so that no stale touch state
     * survives on this view or its ancestors. An interrupted ink stroke is
     * discarded rather than committed.
     */
    fun cancelActiveGestures() {
        isDrawingInk = false
        currentInkPoints.clear()
        inkScreenPath.reset()
        isDragging = false
        dragStartPoint = null
        dragCurrentPoint = null
        clearMovePreview()
        scroller.forceFinished(true)
        slideAnimator?.end()
        isBookSwiping = false
        slideOffset = 0f
        slideNeighbour = -1
        parent?.requestDisallowInterceptTouchEvent(false)
        invalidate()
    }

    override fun onWindowFocusChanged(hasWindowFocus: Boolean) {
        super.onWindowFocusChanged(hasWindowFocus)
        if (!hasWindowFocus) cancelActiveGestures()
    }

    override fun onDetachedFromWindow() {
        cancelActiveGestures()
        super.onDetachedFromWindow()
    }

    // --- Book mode turning ---

    /**
     * Turns one page in book mode: slides to the neighbouring page, or
     * bounces at either end. The new page starts at fit, and onPageChanged
     * fires once when the slide lands. Swipes and edge taps call this after
     * [BookTurnPolicy] allows them; hardware keys can call it directly.
     * Returns false when nothing could turn (not book mode, nothing loaded).
     */
    fun turnPage(direction: BookTurnPolicy.Direction): Boolean {
        if (!isBookMode || pageBitmaps.isEmpty()) return false
        // Land a slide still running first, so rapid turns each count.
        val wasSliding = slideAnimator != null
        slideAnimator?.end()
        if (wasSliding) slideOffset = 0f
        isBookSwiping = false
        resetToFit()

        when (val turn = bookPager.turn(direction)) {
            is BookPager.Turn.Slide -> {
                slideNeighbour = turn.to
                // Next slides the page off to the left, previous to the right.
                animateSlideOffset(slideOffset, -direction.delta * width.toFloat()) {
                    slideOffset = 0f
                    slideNeighbour = -1
                    bookPager.finishSlide()
                }
            }

            is BookPager.Turn.Bounce -> {
                slideNeighbour = -1
                if (slideOffset != 0f) {
                    // Released a rubber-banded drag at an end: spring back.
                    animateSlideOffset(slideOffset, 0f) {}
                } else {
                    val nudge = -direction.delta * width * BOUNCE_FRACTION
                    animateSlideOffset(0f, nudge, BOUNCE_DURATION_MS) {
                        animateSlideOffset(nudge, 0f, BOUNCE_DURATION_MS) {}
                    }
                }
            }
        }
        return true
    }

    private fun bookEdgeTapTurn(e: MotionEvent): BookTurnPolicy.Direction? =
        BookTurnPolicy.edgeTapTurnFor(
            isBookMode,
            annotationMode,
            currentScale,
            e.x,
            width.toFloat(),
            density
        )

    private fun resetToFit() {
        scroller.forceFinished(true)
        currentScale = minScale
        panX = 0f
        panY = 0f
    }

    private fun animateSlideOffset(
        from: Float,
        to: Float,
        durationMs: Long = SLIDE_DURATION_MS,
        onEnd: () -> Unit
    ) {
        slideAnimator?.removeAllListeners()
        slideAnimator?.cancel()
        slideOffset = from
        val animator = ValueAnimator.ofFloat(from, to).apply {
            duration = durationMs
            interpolator = DecelerateInterpolator()
            addUpdateListener {
                slideOffset = it.animatedValue as Float
                invalidate()
            }
        }
        animator.addListener(object : AnimatorListenerAdapter() {
            override fun onAnimationEnd(a: Animator) {
                if (slideAnimator === animator) slideAnimator = null
                slideOffset = to
                onEnd()
                invalidate()
            }
        })
        slideAnimator = animator
        animator.start()
    }

    /** Book mode swipe that is following the finger, at fit. */
    private fun dragBookSwipe(totalDx: Float) {
        isBookSwiping = true
        val neighbour = bookPager.currentPage + if (totalDx < 0f) 1 else -1
        if (neighbour in pageBitmaps.indices) {
            slideNeighbour = neighbour
            slideOffset = totalDx
        } else {
            // Nothing that way: rubber-band so the bounce is felt.
            slideNeighbour = -1
            slideOffset = totalDx * RUBBER_BAND
        }
        invalidate()
    }

    private fun releaseBookSwipe() {
        if (!isBookSwiping) return
        isBookSwiping = false
        val totalDx = if (slideNeighbour >= 0) slideOffset else slideOffset / RUBBER_BAND
        val direction = BookTurnPolicy.swipeReleaseTurnFor(
            dragX = totalDx,
            velocityX = bookSwipeVelocityX,
            viewWidth = width.toFloat(),
            flingVelocity = FLING_VELOCITY_DP * density
        )
        if (direction != null) turnPage(direction) else settleBookSwipe()
    }

    private fun settleBookSwipe() {
        isBookSwiping = false
        animateSlideOffset(slideOffset, 0f) { slideNeighbour = -1 }
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
            val pdfX = (contentX - pageXOffsets[pi]) / renderScales[pi]
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
        val pageX = pageXOffsets[pageIndex]
        val pdfX1 = (startCX - pageX) / rs
        val pdfY1 = ph - (localStartY / rs)
        val pdfX2 = (endCX - pageX) / rs
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
        val pdfTouch = screenToPdfPoint(event.x, event.y) ?: return
        val hit = AnnotationHitTester.hitTest(pdfTouch.point, annotations, pdfTouch.pageIndex)
        if (hit != null) {
            annotations = annotations.filter { it.id != hit.id }
            onAnnotationsChangedListener?.invoke()
        }
    }

    private fun handleMoveTouch(event: MotionEvent) {
        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                val pdfTouch = screenToPdfPoint(event.x, event.y) ?: return
                val hit = AnnotationHitTester.hitTest(
                    pdfTouch.point,
                    annotations,
                    pdfTouch.pageIndex
                )
                if (hit != null) {
                    movingAnnotation = hit
                    movingPreviewAnnotation = hit
                    moveStartPdfPoint = pdfTouch.point
                    invalidate()
                }
            }

            MotionEvent.ACTION_MOVE -> {
                val annotation = movingAnnotation ?: return
                val startPoint = moveStartPdfPoint ?: return
                val pdfTouch = screenToPdfPoint(event.x, event.y, annotation.page) ?: return
                val delta = AnnotationGeometry.clampTranslation(
                    annotation,
                    pdfTouch.point.x - startPoint.x,
                    pdfTouch.point.y - startPoint.y,
                    pageWidths[annotation.page].toFloat(),
                    pageHeights[annotation.page].toFloat()
                )
                movingPreviewAnnotation = AnnotationGeometry.translate(annotation, delta.x, delta.y)
                invalidate()
            }

            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                val annotation = movingAnnotation
                val preview = movingPreviewAnnotation
                if (annotation != null && preview != null && preview != annotation) {
                    annotations = annotations.map { existing ->
                        if (existing.id == annotation.id) preview else existing
                    }
                    onAnnotationsChangedListener?.invoke()
                }
                clearMovePreview()
                invalidate()
            }
        }
    }

    // --- Text mode ---

    private fun handleTextTap(event: MotionEvent) {
        val pdfTouch = screenToPdfPoint(event.x, event.y) ?: return
        val point = pdfTouch.point
        val hit = AnnotationHitTester.hitTest(point, annotations, pdfTouch.pageIndex)
        val annotation = if (hit?.type == "text" || hit?.type == "freeText") hit else null
        onTextInputRequested?.invoke(pdfTouch.pageIndex, point, annotation)
    }

    fun addTextAnnotation(page: Int, point: AnnotationPoint, text: String) {
        val annotation = buildTextAnnotation(text = text, page = page, point = point)
        annotations = annotations + annotation
        onAnnotationsChangedListener?.invoke()
    }

    fun updateTextAnnotation(annotationId: String, text: String) {
        val existing = annotations.find { it.id == annotationId } ?: return
        val updated = buildTextAnnotation(text = text, page = existing.page, existing = existing)
        annotations = annotations.map { annotation ->
            if (annotation.id == annotationId) updated else annotation
        }
        onAnnotationsChangedListener?.invoke()
    }

    private fun buildTextAnnotation(
        text: String,
        page: Int,
        point: AnnotationPoint? = null,
        existing: AnnotationModel? = null
    ): AnnotationModel {
        val fontSize = existing?.fontSize ?: 16f
        val padding = 4f
        val paint = Paint().apply {
            textSize = fontSize
            typeface = AnnotationRenderer.resolveTypeface(
                context,
                existing?.fontFamily ?: annotationFontFamily
            )
        }
        val textWidth = paint.measureText(text)
        val height = fontSize * 1.2f + padding * 2
        val bounds = if (existing != null && existing.bounds != null) {
            AnnotationBounds(
                existing.bounds.x,
                existing.bounds.y + existing.bounds.height - height,
                textWidth + padding * 2,
                height
            )
        } else {
            val anchorPoint = requireNotNull(point)
            AnnotationBounds(
                anchorPoint.x,
                anchorPoint.y - fontSize - padding,
                textWidth + padding * 2,
                height
            )
        }

        return AnnotationModel(
            id = existing?.id ?: UUID.randomUUID().toString(),
            type = existing?.type ?: "freeText",
            page = existing?.page ?: page,
            color = existing?.color ?: annotationColor,
            bounds = bounds,
            contents = text,
            fontSize = fontSize,
            fontFamily = existing?.fontFamily ?: annotationFontFamily,
            createdAt = existing?.createdAt ?: System.currentTimeMillis() / 1000.0
        )
    }

    // --- Stamp mode ---

    private fun handleStampTap(event: MotionEvent) {
        val text = stampText ?: return
        val pdfTouch = screenToPdfPoint(event.x, event.y) ?: return
        val half = stampSize / 2f
        val annotation = AnnotationModel(
            id = UUID.randomUUID().toString(),
            type = "stamp",
            page = pdfTouch.pageIndex,
            color = annotationColor,
            bounds = AnnotationBounds(
                pdfTouch.point.x - half,
                pdfTouch.point.y - half,
                stampSize,
                stampSize
            ),
            text = text,
            createdAt = System.currentTimeMillis() / 1000.0
        )
        annotations = annotations + annotation
        onAnnotationsChangedListener?.invoke()
    }

    // --- Helpers ---

    private fun pageIndexAtContentY(contentY: Float): Int {
        // Book mode: every page shares one slot, so a touch is on the page shown.
        if (isBookMode) return bookPager.currentPage
        for (i in pageYOffsets.indices.reversed()) {
            if (pageYOffsets[i] <= contentY) return i
        }
        return 0
    }

    private data class PdfTouchPoint(val pageIndex: Int, val point: AnnotationPoint)

    private fun clearMovePreview() {
        movingAnnotation = null
        movingPreviewAnnotation = null
        moveStartPdfPoint = null
    }

    private fun screenToPdfPoint(
        screenX: Float,
        screenY: Float,
        forcedPageIndex: Int? = null
    ): PdfTouchPoint? {
        val contentX = (screenX + panX) / currentScale
        val contentY = (screenY + panY) / currentScale
        val pageIndex = forcedPageIndex ?: pageIndexAtContentY(contentY)
        if (pageIndex < 0 || pageIndex >= pageYOffsets.size) return null

        val localY = contentY - pageYOffsets[pageIndex]
        val pdfX = (contentX - pageXOffsets[pageIndex]) / renderScales[pageIndex]
        val pdfY = pageHeights[pageIndex] - (localY / renderScales[pageIndex])
        return PdfTouchPoint(pageIndex, AnnotationPoint(pdfX, pdfY))
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
        if (isBookMode) return bookPager.currentPage
        val centerY = (panY + height / 2f) / currentScale
        for (i in pageYOffsets.indices.reversed()) {
            if (pageYOffsets[i] <= centerY) return i
        }
        return 0
    }

    fun scrollToPage(pageIndex: Int) {
        if (pageIndex < 0 || pageIndex >= pageYOffsets.size) return
        if (isBookMode) {
            // The page prop jumps straight there, at fit, with no slide.
            slideAnimator?.removeAllListeners()
            slideAnimator?.cancel()
            slideAnimator = null
            isBookSwiping = false
            slideOffset = 0f
            slideNeighbour = -1
            resetToFit()
            bookPager.jumpTo(pageIndex) // reports through notifyPageChange
            invalidate()
            return
        }
        panY = pageYOffsets[pageIndex] * currentScale
        constrainPan()
        invalidate()
        notifyPageChange()
    }

    private fun notifyPageChange() {
        val page = getVisiblePage()
        if (page != lastNotifiedPage) {
            lastNotifiedPage = page
            val pw = if (page < pageWidths.size) pageWidths[page] else 0
            val ph = if (page < pageHeights.size) pageHeights[page] else 0
            onPageChangeListener?.invoke(page, pageBitmaps.size, pw, ph)
        }
    }

    fun recycle() {
        pageBitmaps.forEach { it.recycle() }
        pageBitmaps.clear()
        pageXOffsets.clear()
        pageYOffsets.clear()
        slideAnimator?.removeAllListeners()
        slideAnimator?.cancel()
        slideAnimator = null
        isBookSwiping = false
        slideOffset = 0f
        slideNeighbour = -1
        pageWidths.clear()
        pageHeights.clear()
        renderScales.clear()
        currentInkPoints.clear()
        inkScreenPath.reset()
        dragStartPoint = null
        dragCurrentPoint = null
        isDragging = false
        isDrawingInk = false
        clearMovePreview()
        totalHeight = 0f
        lastNotifiedPage = -1
    }

    private companion object {
        const val SLIDE_DURATION_MS = 250L
        const val BOUNCE_DURATION_MS = 120L

        /** How far an edge tap or key nudges the page at either end. */
        const val BOUNCE_FRACTION = 0.06f

        /** How much of the finger's travel the page follows at either end. */
        const val RUBBER_BAND = 0.3f

        /** A release faster than this turns the page even after a short drag. */
        const val FLING_VELOCITY_DP = 500f
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
        override fun onDown(e: MotionEvent): Boolean {
            // Turn or pan is decided once per gesture, at touch down.
            bookSwipeAction =
                BookTurnPolicy.swipeActionFor(isBookMode, annotationMode, currentScale)
            bookSwipeDownX = e.x
            bookSwipeVelocityX = 0f
            return true
        }

        override fun onSingleTapUp(e: MotionEvent): Boolean {
            val direction = bookEdgeTapTurn(e) ?: return false
            turnPage(direction)
            return true
        }

        override fun onScroll(e1: MotionEvent?, e2: MotionEvent, dx: Float, dy: Float): Boolean {
            if (isBookMode && bookSwipeAction == BookTurnPolicy.SwipeAction.TURN) {
                dragBookSwipe(e2.x - (e1?.x ?: bookSwipeDownX))
                return true
            }
            panX += dx
            panY += dy
            constrainPan()
            invalidate()
            notifyPageChange()
            return true
        }

        override fun onFling(e1: MotionEvent?, e2: MotionEvent, vx: Float, vy: Float): Boolean {
            if (isBookMode && bookSwipeAction == BookTurnPolicy.SwipeAction.TURN) {
                // Picked up when the finger lifts, in releaseBookSwipe.
                bookSwipeVelocityX = vx
                return true
            }
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
            // In book mode a quick second tap on an edge is another turn, not a zoom.
            bookEdgeTapTurn(e)?.let {
                turnPage(it)
                return true
            }
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
