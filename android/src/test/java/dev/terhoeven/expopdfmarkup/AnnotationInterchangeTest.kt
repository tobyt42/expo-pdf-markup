package dev.terhoeven.expopdfmarkup

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

class AnnotationInterchangeTest {
    private fun fixtureJson(): String =
        requireNotNull(javaClass.getResource("/annotations-v1.json")).readText()

    private fun fixture(): AnnotationsData = AnnotationSerializer.deserialize(fixtureJson())!!

    private fun jsonValue(value: Any): Any = when (value) {
        is JSONObject -> value.keys().asSequence().associateWith { jsonValue(value.get(it)) }
        is JSONArray -> (0 until value.length()).map { jsonValue(value.get(it)) }
        is Number -> value.toDouble()
        else -> value
    }

    @Test
    fun sharedV1MarksPreservePlacementContentAndStyleAfterRepeatedReopen() {
        val original = fixture()
        assertEquals(1, original.version)
        assertEquals(8, original.annotations.size)
        var reopened = original
        repeat(5) {
            reopened = AnnotationSerializer.deserialize(AnnotationSerializer.serialize(reopened))!!
        }
        assertEquals(original, reopened)
        assertEquals(
            "No v1 fields may disappear or change during decoding and repeated encoding",
            jsonValue(JSONObject(fixtureJson())),
            jsonValue(JSONObject(AnnotationSerializer.serialize(reopened)))
        )
        assertEquals(
            listOf("ink", "highlight", "underline", "text", "freeText", "stamp", "stamp", "stamp"),
            reopened.annotations.map { it.type }
        )
        assertEquals(listOf("♫", "★", "🎵"), reopened.annotations.takeLast(3).map { it.text })
    }

    @Test
    fun sharedV1MarksHaveMatchingMoveAndEraseTargetsOnTheVisiblePage() {
        val annotations = fixture().annotations
        val targets = listOf(
            AnnotationPoint(120f, 160f),
            AnnotationPoint(150f, 312f),
            AnnotationPoint(160f, 390f),
            AnnotationPoint(220f, 470f),
            AnnotationPoint(220f, 540f),
            AnnotationPoint(44f, 724f),
            AnnotationPoint(294f, 724f),
            AnnotationPoint(554f, 724f)
        )
        annotations.forEachIndexed { index, annotation ->
            val target = targets[index]
            assertEquals(annotation.id, AnnotationHitTester.hitTest(target, annotations, 0)?.id)
            val moved = AnnotationGeometry.translate(annotation, 12f, -16f)
            assertEquals(
                annotation.id,
                AnnotationHitTester.hitTest(
                    AnnotationPoint(target.x + 12f, target.y - 16f),
                    listOf(moved),
                    0
                )?.id
            )
            assertNotNull(AnnotationGeometry.outlineBounds(moved))
            assertEquals(annotation, AnnotationGeometry.translate(moved, -12f, 16f))
        }
        assertEquals(
            AnnotationBounds(30f, 90f, 160f, 80f),
            AnnotationGeometry.outlineBounds(annotations[0])
        )
        assertEquals(
            AnnotationBounds(60f, 300f, 180f, 24f),
            AnnotationGeometry.outlineBounds(annotations[1])
        )
    }
}
