package dev.terhoeven.expopdfmarkup

import android.content.Context
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import expo.modules.kotlin.AppContext
import expo.modules.kotlin.viewevent.EventDispatcher
import expo.modules.kotlin.views.ExpoView
import java.io.File

class ExpoPdfMarkupView(context: Context, appContext: AppContext) : ExpoView(context, appContext) {
    private val pdfView = ContinuousPdfView(context).apply {
        layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT)
    }

    private val onPageChanged by EventDispatcher()
    private val onLoadComplete by EventDispatcher()
    private val onError by EventDispatcher()

    private var renderer: PdfRenderer? = null
    private var fileDescriptor: ParcelFileDescriptor? = null
    private var currentSource: String? = null

    init {
        addView(pdfView)
        pdfView.onPageChangeListener = { page, pageCount ->
            onPageChanged(mapOf("page" to page, "pageCount" to pageCount))
        }
    }

    fun loadPdf(source: String) {
        if (source == currentSource) return
        currentSource = source

        try {
            close()
            val file = File(source)
            if (!file.exists()) {
                onError(mapOf("message" to "File not found: $source"))
                return
            }
            val fd = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
            fileDescriptor = fd
            val r = PdfRenderer(fd)
            renderer = r
            onLoadComplete(mapOf("pageCount" to r.pageCount))
            if (width > 0) {
                pdfView.loadPages(r, width)
            } else {
                post { renderer?.let { pdfView.loadPages(it, width) } }
            }
        } catch (e: Exception) {
            onError(mapOf("message" to "Failed to load PDF: ${e.message}"))
        }
    }

    fun goToPage(pageIndex: Int) {
        pdfView.scrollToPage(pageIndex)
    }

    fun setPageBackgroundColor(color: Int?) {
        pdfView.pageBackgroundColor = color ?: android.graphics.Color.rgb(235, 235, 235)
        pdfView.setBackgroundColor(pdfView.pageBackgroundColor)
    }

    private fun close() {
        pdfView.recycle()
        renderer?.close()
        renderer = null
        fileDescriptor?.close()
        fileDescriptor = null
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        close()
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        if (w > 0 && w != oldw) {
            renderer?.let { pdfView.loadPages(it, w) }
        }
    }
}
