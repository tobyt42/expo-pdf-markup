package dev.terhoeven.expopdfmarkup

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.pdf.PdfRenderer
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.view.View
import android.widget.OverScroller

class ContinuousPdfView(context: Context) : View(context) {
    private val pageBitmaps = mutableListOf<Bitmap>()
    private val pageYOffsets = mutableListOf<Float>()
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

    fun loadPages(renderer: PdfRenderer, viewWidth: Int) {
        recycle()
        if (viewWidth <= 0) return
        setBackgroundColor(pageBackgroundColor)

        var yOffset = 0f
        for (i in 0 until renderer.pageCount) {
            if (i > 0) yOffset += pageGap

            val page = renderer.openPage(i)
            val scale = viewWidth.toFloat() / page.width.toFloat()
            val bmpH = (page.height * scale).toInt()

            val bmp = Bitmap.createBitmap(viewWidth, bmpH, Bitmap.Config.ARGB_8888)
            Canvas(bmp).drawColor(Color.WHITE)

            val m = Matrix()
            m.setScale(scale, scale)
            page.render(bmp, null, m, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
            page.close()

            pageYOffsets.add(yOffset)
            pageBitmaps.add(bmp)
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
            }
        }

        canvas.restore()
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        scaleDetector.onTouchEvent(event)
        gestureDetector.onTouchEvent(event)
        parent?.requestDisallowInterceptTouchEvent(true)
        return true
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
