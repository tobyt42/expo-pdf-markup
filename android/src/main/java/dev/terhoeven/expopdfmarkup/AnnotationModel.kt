package dev.terhoeven.expopdfmarkup

data class AnnotationPoint(val x: Float, val y: Float)

data class AnnotationBounds(val x: Float, val y: Float, val width: Float, val height: Float) {
    fun contains(point: AnnotationPoint): Boolean =
        point.x >= x && point.x <= x + width && point.y >= y && point.y <= y + height
}

data class AnnotationModel(
    val id: String,
    val type: String,
    val page: Int,
    val color: String,
    val lineWidth: Float? = null,
    val alpha: Float? = null,
    val paths: List<List<AnnotationPoint>>? = null,
    val bounds: AnnotationBounds? = null,
    val contents: String? = null,
    val fontSize: Float? = null,
    val createdAt: Double? = null
)

data class AnnotationsData(
    val version: Int = 1,
    val annotations: List<AnnotationModel> = emptyList()
)
