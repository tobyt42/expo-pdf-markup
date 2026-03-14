package dev.terhoeven.expopdfmarkup

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Typeface

object AnnotationRenderer {

    fun drawAnnotations(
        canvas: Canvas,
        annotations: List<AnnotationModel>,
        pageIndex: Int,
        pageYOffset: Float,
        renderScale: Float,
        pageHeight: Int,
        context: Context
    ) {
        for (annotation in annotations) {
            if (annotation.page != pageIndex) continue
            when (annotation.type) {
                "ink" -> drawInk(canvas, annotation, pageYOffset, renderScale, pageHeight)

                "highlight" -> drawHighlight(
                    canvas,
                    annotation,
                    pageYOffset,
                    renderScale,
                    pageHeight
                )

                "underline" -> drawUnderline(
                    canvas,
                    annotation,
                    pageYOffset,
                    renderScale,
                    pageHeight
                )

                "freeText", "text" -> drawFreeText(
                    canvas,
                    annotation,
                    pageYOffset,
                    renderScale,
                    pageHeight,
                    context
                )
            }
        }
    }

    private fun drawInk(
        canvas: Canvas,
        annotation: AnnotationModel,
        pageYOffset: Float,
        renderScale: Float,
        pageHeight: Int
    ) {
        val paths = annotation.paths ?: return
        val paint = Paint().apply {
            color = AnnotationSerializer.colorFromHex(annotation.color)
            strokeWidth = (annotation.lineWidth ?: 2f) * renderScale
            style = Paint.Style.STROKE
            isAntiAlias = true
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
        }
        for (stroke in paths) {
            if (stroke.isEmpty()) continue
            val path = Path()
            for ((i, pt) in stroke.withIndex()) {
                val cx = pt.x * renderScale
                val cy = (pageHeight - pt.y) * renderScale + pageYOffset
                if (i == 0) path.moveTo(cx, cy) else path.lineTo(cx, cy)
            }
            canvas.drawPath(path, paint)
        }
    }

    private fun drawHighlight(
        canvas: Canvas,
        annotation: AnnotationModel,
        pageYOffset: Float,
        renderScale: Float,
        pageHeight: Int
    ) {
        val bounds = annotation.bounds ?: return
        val alpha = annotation.alpha ?: 0.5f
        val color = AnnotationSerializer.colorFromHex(annotation.color)
        val paint = Paint().apply {
            this.color = color
            this.alpha = (alpha * 255).toInt()
            style = Paint.Style.FILL
            isAntiAlias = true
        }
        val left = bounds.x * renderScale
        val top = (pageHeight - bounds.y - bounds.height) * renderScale + pageYOffset
        val right = left + bounds.width * renderScale
        val bottom = top + bounds.height * renderScale
        canvas.drawRect(left, top, right, bottom, paint)
    }

    private fun drawUnderline(
        canvas: Canvas,
        annotation: AnnotationModel,
        pageYOffset: Float,
        renderScale: Float,
        pageHeight: Int
    ) {
        val bounds = annotation.bounds ?: return
        val paint = Paint().apply {
            color = AnnotationSerializer.colorFromHex(annotation.color)
            strokeWidth = 1f * renderScale
            style = Paint.Style.STROKE
            isAntiAlias = true
        }
        val left = bounds.x * renderScale
        val bottom = (pageHeight - bounds.y) * renderScale + pageYOffset
        val right = left + bounds.width * renderScale
        canvas.drawLine(left, bottom, right, bottom, paint)
    }

    private fun drawFreeText(
        canvas: Canvas,
        annotation: AnnotationModel,
        pageYOffset: Float,
        renderScale: Float,
        pageHeight: Int,
        context: Context
    ) {
        val bounds = annotation.bounds ?: return
        val text = annotation.contents ?: return
        val paint = Paint().apply {
            color = AnnotationSerializer.colorFromHex(annotation.color)
            textSize = (annotation.fontSize ?: 16f) * renderScale
            typeface = resolveTypeface(context, annotation.fontFamily)
            isAntiAlias = true
        }
        val left = bounds.x * renderScale
        val top = (pageHeight - bounds.y - bounds.height) * renderScale + pageYOffset
        canvas.drawText(text, left, top + paint.textSize, paint)
    }

    /** Resolve a typeface by family name. Tries app assets first (where expo-font places fonts),
     *  then falls back to system typeface resolution. */
    fun resolveTypeface(context: Context, fontFamily: String?): Typeface {
        if (fontFamily == null) return Typeface.DEFAULT
        return try {
            Typeface.createFromAsset(context.assets, "fonts/$fontFamily.ttf")
        } catch (_: Exception) {
            Typeface.create(fontFamily, Typeface.NORMAL)
        }
    }
}
