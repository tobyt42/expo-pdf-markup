package dev.terhoeven.expopdfmarkup

import android.app.AlertDialog
import android.content.Context
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import android.widget.EditText
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
    private val onAnnotationsChanged by EventDispatcher()

    private var renderer: PdfRenderer? = null
    private var fileDescriptor: ParcelFileDescriptor? = null
    private var currentSource: String? = null
    private var pendingAnnotationsJson: String? = null

    init {
        addView(pdfView)
        pdfView.onPageChangeListener = { page, pageCount ->
            onPageChanged(mapOf("page" to page, "pageCount" to pageCount))
        }
        pdfView.onAnnotationsChangedListener = {
            emitAnnotationsChanged()
        }
        pdfView.onTextInputRequested = { page, point ->
            showTextInputDialog(page, point)
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
            // Re-apply pending annotations after load
            pendingAnnotationsJson?.let { loadAnnotations(it) }
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

    fun loadAnnotations(json: String?) {
        pendingAnnotationsJson = json
        if (json.isNullOrEmpty()) {
            pdfView.annotations = emptyList()
            return
        }
        val data = AnnotationSerializer.deserialize(json) ?: return
        // Dedup by id — keep last occurrence
        val seen = mutableSetOf<String>()
        val deduped = data.annotations.reversed().filter { seen.add(it.id) }.reversed()
        pdfView.annotations = deduped
    }

    fun setAnnotationMode(mode: String?) {
        pdfView.annotationMode = mode ?: "none"
    }

    fun setAnnotationColor(color: String?) {
        pdfView.annotationColor = color ?: "#000000"
    }

    fun setAnnotationLineWidth(width: Double?) {
        pdfView.annotationLineWidth = width?.toFloat() ?: 2f
    }

    private fun emitAnnotationsChanged() {
        val data = AnnotationsData(version = 1, annotations = pdfView.annotations)
        val json = AnnotationSerializer.serialize(data)
        pendingAnnotationsJson = json
        onAnnotationsChanged(mapOf("annotations" to json))
    }

    private fun showTextInputDialog(page: Int, point: AnnotationPoint) {
        val editText = EditText(context).apply {
            hint = "Enter text"
            setPadding(48, 32, 48, 32)
        }
        AlertDialog.Builder(context)
            .setTitle("Add Text")
            .setView(editText)
            .setPositiveButton("Add") { _, _ ->
                val text = editText.text.toString().trim()
                if (text.isNotEmpty()) {
                    pdfView.addTextAnnotation(page, point, text)
                }
            }
            .setNegativeButton("Cancel", null)
            .show()
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
