package dev.terhoeven.expopdfmarkup

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.sqrt

object AnnotationHitTester {

    fun hitTest(
        point: AnnotationPoint,
        annotations: List<AnnotationModel>,
        pageIndex: Int
    ): AnnotationModel? {
        // Return last (topmost) matching annotation
        for (annotation in annotations.reversed()) {
            if (annotation.page != pageIndex) continue
            when (annotation.type) {
                "ink" -> {
                    val tolerance = max(annotation.lineWidth ?: 2f, 10f)
                    if (hitTestInk(point, annotation, tolerance)) return annotation
                }

                "highlight", "underline", "freeText", "text" -> {
                    val bounds = annotation.bounds ?: continue
                    if (bounds.contains(point)) return annotation
                }
            }
        }
        return null
    }

    private fun hitTestInk(
        point: AnnotationPoint,
        annotation: AnnotationModel,
        tolerance: Float
    ): Boolean {
        val paths = annotation.paths ?: return false
        for (stroke in paths) {
            for (i in 0 until stroke.size - 1) {
                if (distanceToSegment(point, stroke[i], stroke[i + 1]) <= tolerance) {
                    return true
                }
            }
            // Also check single-point strokes
            if (stroke.size == 1) {
                val dx = point.x - stroke[0].x
                val dy = point.y - stroke[0].y
                if (sqrt(dx * dx + dy * dy) <= tolerance) return true
            }
        }
        return false
    }

    internal fun distanceToSegment(
        point: AnnotationPoint,
        a: AnnotationPoint,
        b: AnnotationPoint
    ): Float {
        val dx = b.x - a.x
        val dy = b.y - a.y
        val lenSq = dx * dx + dy * dy
        if (lenSq == 0f) {
            // a and b are the same point
            val px = point.x - a.x
            val py = point.y - a.y
            return sqrt(px * px + py * py)
        }
        var t = ((point.x - a.x) * dx + (point.y - a.y) * dy) / lenSq
        t = t.coerceIn(0f, 1f)
        val projX = a.x + t * dx
        val projY = a.y + t * dy
        val ex = point.x - projX
        val ey = point.y - projY
        return sqrt(ex * ex + ey * ey)
    }
}
