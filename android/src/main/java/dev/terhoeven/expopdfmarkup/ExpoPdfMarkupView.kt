package dev.terhoeven.expopdfmarkup

import android.app.AlertDialog
import android.content.Context
import android.graphics.pdf.PdfRenderer
import android.os.Build
import android.os.ParcelFileDescriptor
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.ViewTreeObserver
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
    private var lastLoadedSource: String? = null
    private var pendingAnnotationsJson: String? = null
    private var sourceToReloadOnAttach: String? = null
    private var savedScrollState: ContinuousPdfView.ScrollState? = null
    var useJsTextDialog: Boolean = false

    private var pendingTextPage: Int = -1
    private var pendingTextPoint: AnnotationPoint? = null
    private var pendingTextAnnotationId: String? = null

    /** When a text input elsewhere lets go of focus, book mode takes the keys back. */
    private val focusChangeListener = ViewTreeObserver.OnGlobalFocusChangeListener {
            oldFocus,
            newFocus
        ->
        if (newFocus == null && oldFocus?.onCheckIsTextEditor() == true) post { claimKeyFocus() }
    }

    init {
        addView(pdfView)
        // Book mode takes key focus for pedals and keyboards; it has nothing to highlight.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) defaultFocusHighlightEnabled = false
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
        sourceToReloadOnAttach = null // Explicit load supersedes any pending reload-on-attach
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
            lastLoadedSource = source
            onLoadComplete(mapOf("pageCount" to r.pageCount))
            if (width > 0 && (height > 0 || !pdfView.isBookMode)) {
                pdfView.loadPages(r, width, height)
            } else {
                post { renderer?.let { pdfView.loadPages(it, width, height) } }
            }
            // Re-apply pending annotations after load
            pendingAnnotationsJson?.let { loadAnnotations(it) }
            claimKeyFocus()
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

    /** `"continuous"` (default) or `"book"`: one page at a time, turned sideways. */
    var displayMode: String = "continuous"
        private set

    /** Switches display mode, keeping the reader on the page they were on. */
    fun setDisplayMode(mode: String?) {
        val newMode = if (mode == "book") "book" else "continuous"
        if (newMode == displayMode) return
        displayMode = newMode
        val page = pdfView.currentPage
        pdfView.isBookMode = newMode == "book"
        renderer?.let { pdfView.loadPages(it, width, height, startPage = page) }
        // Only book mode handles keys, so only book mode takes focus.
        isFocusable = pdfView.isBookMode
        isFocusableInTouchMode = pdfView.isBookMode
        if (pdfView.isBookMode) {
            claimKeyFocus()
        } else if (hasFocus()) {
            clearFocus()
        }
    }

    /** Whether a text input in this window has focus, so keys belong to it. */
    private fun textInputHasFocus(): Boolean = rootView.findFocus()?.onCheckIsTextEditor() == true

    /**
     * Takes key focus in book mode, so a keyboard or page-turner pedal turns
     * the page without the host app doing anything. Never takes it from a
     * text input.
     */
    private fun claimKeyFocus() {
        if (!pdfView.isBookMode || !isAttachedToWindow || hasFocus() || textInputHasFocus()) return
        requestFocus()
    }

    override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
        if (ev.actionMasked == MotionEvent.ACTION_DOWN) claimKeyFocus()
        return super.dispatchTouchEvent(ev)
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        val direction = BookTurnPolicy.keyTurnFor(
            keyCode,
            isBookMode = pdfView.isBookMode,
            textInputHasFocus = textInputHasFocus(),
            hasModifiers = !event.hasNoModifiers()
        ) ?: return super.onKeyDown(keyCode, event)
        // A key turns even mid-stroke: drop the unfinished ink rather than carry it to the new page.
        pdfView.cancelActiveGestures()
        turnPage(direction)
        return true
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent): Boolean {
        val mapped = BookTurnPolicy.keyTurnFor(
            keyCode,
            isBookMode = pdfView.isBookMode,
            textInputHasFocus = textInputHasFocus(),
            hasModifiers = !event.hasNoModifiers()
        )
        return mapped != null || super.onKeyUp(keyCode, event)
    }

    /**
     * Turns one page in book mode, with the same slide, bounce and single
     * onPageChanged as a swipe or edge tap. No-op in continuous mode.
     */
    fun turnPage(direction: BookTurnPolicy.Direction): Boolean = pdfView.turnPage(direction)

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

    fun setStampText(value: String?) {
        pdfView.stampText = value
    }

    fun setStampSize(value: Double?) {
        pdfView.stampSize = value?.toFloat() ?: 48f
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
        viewTreeObserver.removeOnGlobalFocusChangeListener(focusChangeListener)
        super.onDetachedFromWindow()
        pdfView.cancelActiveGestures()
        // Save the successfully-loaded source before close() so we can reload on re-attach.
        // (currentSource is always null after loadPdf() because close() resets it there.)
        sourceToReloadOnAttach = lastLoadedSource
        lastLoadedSource = null
        savedScrollState = pdfView.captureScrollState()
        close()
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        viewTreeObserver.addOnGlobalFocusChangeListener(focusChangeListener)
        post { claimKeyFocus() }
        sourceToReloadOnAttach?.let { source ->
            sourceToReloadOnAttach = null
            pdfView.pendingScrollRestore = savedScrollState
            savedScrollState = null
            loadPdf(source)
        }
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        val r = renderer ?: return
        if (pdfView.isBookMode) {
            // Rotation or resize: re-fit the page in view and stay on it.
            if (w > 0 && h > 0 && (w != oldw || h != oldh)) {
                pdfView.loadPages(r, w, h, startPage = pdfView.currentPage)
            }
        } else if (w > 0 && w != oldw) {
            pdfView.loadPages(r, w, h)
        }
    }
}
