package dev.terhoeven.expopdfmarkup

object AnnotationGeometry {

    fun outlineBounds(annotation: AnnotationModel): AnnotationBounds? = when (annotation.type) {
        "ink" -> outlineBoundsForInk(annotation)
        "highlight", "underline", "freeText", "text" -> annotation.bounds
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

            "highlight", "underline", "freeText", "text" -> {
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
