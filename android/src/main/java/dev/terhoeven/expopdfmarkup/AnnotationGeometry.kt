package dev.terhoeven.expopdfmarkup

object AnnotationGeometry {

    /**
     * Scale a srcWidth/srcHeight rect to fit inside dest, preserving aspect ratio, centered.
     * Deliberately uses the plain-Kotlin [AnnotationBounds] (not android.graphics.RectF) so this
     * stays testable in pure JUnit without Robolectric.
     */
    fun containFitRect(
        srcWidth: Float,
        srcHeight: Float,
        dest: AnnotationBounds
    ): AnnotationBounds {
        if (srcWidth <= 0f || srcHeight <= 0f || dest.width <= 0f || dest.height <= 0f) {
            return dest
        }
        val scale = minOf(dest.width / srcWidth, dest.height / srcHeight)
        val width = srcWidth * scale
        val height = srcHeight * scale
        return AnnotationBounds(
            x = dest.x + (dest.width - width) / 2f,
            y = dest.y + (dest.height - height) / 2f,
            width = width,
            height = height
        )
    }

    fun outlineBounds(annotation: AnnotationModel): AnnotationBounds? = when (annotation.type) {
        "ink" -> outlineBoundsForInk(annotation)
        "highlight", "underline", "freeText", "text", "stamp" -> annotation.bounds
        else -> null
    }

    fun clampTranslation(
        annotation: AnnotationModel,
        deltaX: Float,
        deltaY: Float,
        pageWidth: Float,
        pageHeight: Float
    ): AnnotationPoint {
        val bounds = outlineBounds(annotation) ?: return AnnotationPoint(deltaX, deltaY)
        val minDx = -bounds.x
        val maxDx = pageWidth - (bounds.x + bounds.width)
        val minDy = -bounds.y
        val maxDy = pageHeight - (bounds.y + bounds.height)
        return AnnotationPoint(
            x = deltaX.coerceIn(minDx, maxDx),
            y = deltaY.coerceIn(minDy, maxDy)
        )
    }

    fun translate(annotation: AnnotationModel, deltaX: Float, deltaY: Float): AnnotationModel {
        if (deltaX == 0f && deltaY == 0f) return annotation
        return when (annotation.type) {
            "ink" ->
                annotation.copy(
                    paths =
                        annotation.paths?.map { stroke ->
                            stroke.map { point ->
                                AnnotationPoint(point.x + deltaX, point.y + deltaY)
                            }
                        }
                )

            "highlight", "underline", "freeText", "text", "stamp" -> {
                val bounds = annotation.bounds ?: return annotation
                annotation.copy(
                    bounds =
                        AnnotationBounds(
                            x = bounds.x + deltaX,
                            y = bounds.y + deltaY,
                            width = bounds.width,
                            height = bounds.height
                        )
                )
            }

            else -> annotation
        }
    }

    private fun outlineBoundsForInk(annotation: AnnotationModel): AnnotationBounds? {
        val paths = annotation.paths ?: return null
        var minX = Float.POSITIVE_INFINITY
        var minY = Float.POSITIVE_INFINITY
        var maxX = Float.NEGATIVE_INFINITY
        var maxY = Float.NEGATIVE_INFINITY

        for (stroke in paths) {
            for (point in stroke) {
                minX = minOf(minX, point.x)
                minY = minOf(minY, point.y)
                maxX = maxOf(maxX, point.x)
                maxY = maxOf(maxY, point.y)
            }
        }

        if (!minX.isFinite() || !minY.isFinite()) return null

        val padding = maxOf(annotation.lineWidth ?: 2f, 10f)
        return AnnotationBounds(
            x = minX - padding,
            y = minY - padding,
            width = maxX - minX + padding * 2,
            height = maxY - minY + padding * 2
        )
    }
}
