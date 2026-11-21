package dev.terhoeven.expopdfmarkup

/**
 * Reads the view's annotation set when it is loaded, and writes it after an edit, handing the
 * JSON to [emit] (the view's `onAnnotationsChanged`). Loading never emits.
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

    /**
     * Reads an annotation set given to the view, keeping the last annotation with each id.
     * Returns an empty list for no set, or null when [json] can't be read (keep what is shown).
     * Writes nothing.
     */
    fun annotationsLoaded(json: String?): List<AnnotationModel>? {
        if (json.isNullOrEmpty()) return emptyList()
        val data = AnnotationSerializer.deserialize(json) ?: return null
        val seen = mutableSetOf<String>()
        return data.annotations.reversed().filter { seen.add(it.id) }.reversed()
    }
}
