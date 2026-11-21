package dev.terhoeven.expopdfmarkup

/**
 * Writes the view's annotation set after an edit and hands the JSON to [emit]
 * (the view's `onAnnotationsChanged`).
 */
class AnnotationsChangeEmitter(private val emit: (String) -> Unit) {
    /** Applies from the next write; setting it writes nothing by itself. */
    var inkPointFormat: InkPointFormat = InkPointFormat.OBJECT

    fun annotationsChanged(annotations: List<AnnotationModel>) {
        emit(
            AnnotationSerializer.serialize(
                AnnotationsData(version = 1, annotations = annotations),
                inkPointFormat
            )
        )
    }
}
