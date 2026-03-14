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
    private val onTextInputRequested by EventDispatcher()

    private var renderer: PdfRenderer? = null
    private var fileDescriptor: ParcelFileDescriptor? = null
    private var currentSource: String? = null
    private var pendingAnnotationsJson: String? = null
    var useJsTextDialog: Boolean = false

    private var pendingTextPage: Int = -1
    private var pendingTextPoint: AnnotationPoint? = null
    private var pendingTextAnnotationId: String? = null

    init {
        addView(pdfView)
        pdfView.onPageChangeListener = { page, pageCount, pageWidth, pageHeight ->
            onPageChanged(
                mapOf(
                    "page" to page,
                    "pageCount" to pageCount,
                    "pageWidth" to pageWidth,
                    "pageHeight" to pageHeight
                )
            )
        }
        pdfView.onAnnotationsChangedListener = {
            emitAnnotationsChanged()
        }
        pdfView.onTextInputRequested = { page, point, annotation ->
            if (useJsTextDialog) {
                pendingTextPage = page
                pendingTextPoint = point
                pendingTextAnnotationId = annotation?.id
                val payload = mutableMapOf<String, Any>(
                    "mode" to if (annotation == null) "create" else "edit",
                    "page" to page,
                    "point" to mapOf("x" to point.x, "y" to point.y)
                )
                annotation?.contents?.let { payload["currentText"] = it }
                onTextInputRequested(payload)
            } else {
                showTextInputDialog(page, point, annotation)
            }
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

    fun setAnnotationFontFamily(font: String?) {
        pdfView.annotationFontFamily = font
    }

    private fun emitAnnotationsChanged() {
        val data = AnnotationsData(version = 1, annotations = pdfView.annotations)
        val json = AnnotationSerializer.serialize(data)
        pendingAnnotationsJson = json
        onAnnotationsChanged(mapOf("annotations" to json))
    }

    fun provideTextInput(text: String?) {
        val page = pendingTextPage.also { pendingTextPage = -1 }
        val point = pendingTextPoint.also { pendingTextPoint = null }
        val annotationId = pendingTextAnnotationId.also { pendingTextAnnotationId = null }
        if (page < 0 || point == null || text.isNullOrEmpty()) return
        if (annotationId != null) {
            pdfView.updateTextAnnotation(annotationId, text)
        } else {
            pdfView.addTextAnnotation(page, point, text)
        }
    }

    private fun showTextInputDialog(
        page: Int,
        point: AnnotationPoint,
        annotation: AnnotationModel?
    ) {
        val editText = EditText(context).apply {
            hint = "Enter text"
            setPadding(48, 32, 48, 32)
            setText(annotation?.contents.orEmpty())
            setSelection(text.length)
        }
        AlertDialog.Builder(context)
            .setTitle(if (annotation == null) "Add Text" else "Edit Text")
            .setView(editText)
            .setPositiveButton(if (annotation == null) "Add" else "Update") { _, _ ->
                val text = editText.text.toString().trim()
                if (text.isNotEmpty()) {
                    if (annotation != null) {
                        pdfView.updateTextAnnotation(annotation.id, text)
                    } else {
                        pdfView.addTextAnnotation(page, point, text)
                    }
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
        currentSource = null
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
