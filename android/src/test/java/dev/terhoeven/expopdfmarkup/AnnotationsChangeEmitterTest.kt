package dev.terhoeven.expopdfmarkup

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What the view sends in `onAnnotationsChanged`, through the same emitter the view writes with.
 * The view itself needs the Android framework, so an ink edit is the view's new annotation list.
 */
class AnnotationsChangeEmitterTest {
    private val emitted = mutableListOf<String>()
    private val emitter = AnnotationsChangeEmitter { emitted.add(it) }

    private val drawnStroke = AnnotationModel(
        id = "drawn",
        type = "ink",
        page = 0,
        color = "#FF0000",
        lineWidth = 2f,
        paths = listOf(listOf(AnnotationPoint(80.04f, 120.01f), AnnotationPoint(130.26f, 170.66f)))
    )

    private fun resource(name: String): String =
        requireNotNull(javaClass.getResource(name)).readText()

    private fun inkPoints(json: String): List<Any> {
        val points = mutableListOf<Any>()
        val annotations = JSONObject(json).getJSONArray("annotations")
        for (i in 0 until annotations.length()) {
            val annotation = annotations.getJSONObject(i)
            if (annotation.getString("type") != "ink") continue
            val paths = annotation.getJSONArray("paths")
            for (s in 0 until paths.length()) {
                val stroke = paths.getJSONArray(s)
                for (p in 0 until stroke.length()) points.add(stroke.get(p))
            }
        }
        return points
    }

    @Test
    fun anInkEditIsWrittenInObjectFormByDefault() {
        emitter.annotationsChanged(listOf(drawnStroke))

        assertEquals(1, emitted.size)
        val points = inkPoints(emitted.single())
        assertEquals(2, points.size)
        val first = points[0] as JSONObject
        assertEquals(80.0, first.getDouble("x"), 0.0)
        assertEquals(120.0, first.getDouble("y"), 0.0)
    }

    @Test
    fun anInkEditIsWrittenInArrayFormWithInkPointFormatArray() {
        emitter.inkPointFormat = InkPointFormat.ARRAY

        emitter.annotationsChanged(listOf(drawnStroke))

        assertEquals(1, emitted.size)
        val points = inkPoints(emitted.single())
        assertEquals(2, points.size)
        val second = points[1] as JSONArray
        assertEquals(2, second.length())
        assertEquals(130.3, second.getDouble(0), 0.0)
        assertEquals(170.7, second.getDouble(1), 0.0)
    }

    @Test
    fun changingInkPointFormatAloneWritesNothing() {
        emitter.inkPointFormat = InkPointFormat.ARRAY
        emitter.inkPointFormat = InkPointFormat.OBJECT

        assertTrue(emitted.isEmpty())
    }

    @Test
    fun aSetLoadedInObjectFormIsWrittenInArrayFormOnTheNextEdit() {
        val loaded = AnnotationSerializer.deserialize(resource("/annotations-v1.json"))!!
        emitter.inkPointFormat = InkPointFormat.ARRAY

        emitter.annotationsChanged(loaded.annotations + drawnStroke)

        val points = inkPoints(emitted.single())
        assertTrue(points.size > 2)
        assertTrue(points.all { it is JSONArray })
    }

    @Test
    fun aSetLoadedInArrayFormIsWrittenInObjectFormOnTheNextEdit() {
        val loaded = AnnotationSerializer.deserialize(resource("/annotations-v1-array.json"))!!

        emitter.annotationsChanged(loaded.annotations + drawnStroke)

        val points = inkPoints(emitted.single())
        assertTrue(points.size > 2)
        assertTrue(points.all { it is JSONObject })
    }
}
