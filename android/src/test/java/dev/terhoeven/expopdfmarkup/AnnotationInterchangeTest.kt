package dev.terhoeven.expopdfmarkup

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
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
    fun sharedArrayFormFixtureDecodesToTheSameAnnotationsAsTheObjectFormFixture() {
        val arrayJson = requireNotNull(
            javaClass.getResource("/annotations-v1-array.json")
        ).readText()
        assertEquals(fixture(), AnnotationSerializer.deserialize(arrayJson))
    }

    @Test
    fun sharedCleanUpFixtureIsWrittenExactlyAsExpectedInObjectForm() {
        val input = AnnotationSerializer.deserialize(resource("/ink-cleanup-input.json"))!!
        assertEquals(
            jsonValue(JSONObject(resource("/ink-cleanup-expected-object.json"))),
            jsonValue(JSONObject(AnnotationSerializer.serialize(input)))
        )
    }

    @Test
    fun sharedCleanUpFixtureIsWrittenExactlyAsExpectedInArrayForm() {
        val input = AnnotationSerializer.deserialize(resource("/ink-cleanup-input.json"))!!
        assertEquals(
            jsonValue(JSONObject(resource("/ink-cleanup-expected-array.json"))),
            jsonValue(JSONObject(AnnotationSerializer.serialize(input, InkPointFormat.ARRAY)))
        )
    }

    @Test
    fun arrayFormInkCoordinatesAreWrittenAsTheSameTextsAsObjectForm() {
        val input = AnnotationSerializer.deserialize(resource("/ink-cleanup-input.json"))!!
        val arrayTexts =
            inkCoordinateTexts(AnnotationSerializer.serialize(input, InkPointFormat.ARRAY))
        assertEquals(26, arrayTexts.size)
        assertEquals(inkCoordinateTexts(AnnotationSerializer.serialize(input)), arrayTexts)
    }

    @Test
    fun arrayFormOutputReadsBackAsTheSameAnnotationsAsObjectFormOutput() {
        val input = AnnotationSerializer.deserialize(resource("/ink-cleanup-input.json"))!!
        assertEquals(
            AnnotationSerializer.deserialize(AnnotationSerializer.serialize(input)),
            AnnotationSerializer.deserialize(
                AnnotationSerializer.serialize(input, InkPointFormat.ARRAY)
            )
        )
    }

    @Test
    fun inkPointFormatPropIsArrayOnlyForArray() {
        assertEquals(InkPointFormat.ARRAY, InkPointFormat.fromProp("array"))
        assertEquals(InkPointFormat.OBJECT, InkPointFormat.fromProp("object"))
        assertEquals(InkPointFormat.OBJECT, InkPointFormat.fromProp(null))
        assertEquals(InkPointFormat.OBJECT, InkPointFormat.fromProp("tuple"))
    }

    @Test
    fun everyWrittenInkCoordinateHasAtMostOneDecimalDigitAndNoTrailingZero() {
        val input = AnnotationSerializer.deserialize(resource("/ink-cleanup-input.json"))!!
        val written = AnnotationSerializer.serialize(input)
        val coordinates = inkCoordinateTexts(written)
        assertEquals(
            listOf(
                "307.7", "462.6", "1.8", "12.3", "100", "100", "0", "-1.3", "0.1", "2.7",
                "50", "60", "50", "60", "5", "5", "5", "5", "10.1", "21",
                "200.1", "301", "200.2", "300.9", "200.1", "301"
            ),
            coordinates
        )
        for (text in coordinates) {
            assertTrue("bad coordinate text: $text", Regex("-?\\d+(\\.[1-9])?").matches(text))
            assertTrue("negative zero written: $text", text != "-0")
        }
    }

    private fun resource(name: String): String =
        requireNotNull(javaClass.getResource(name)).readText()

    /** Raw number texts of every ink coordinate in the written JSON, in order. */
    private fun inkCoordinateTexts(json: String): List<String> {
        val texts = mutableListOf<String>()
        var from = 0
        while (true) {
            val start = json.indexOf("\"paths\":", from).takeIf { it >= 0 } ?: break
            var depth = 0
            var end = json.indexOf('[', start)
            do {
                when (json[end]) {
                    '[' -> depth++
                    ']' -> depth--
                }
                end++
            } while (depth > 0)
            val section = json.substring(start + "\"paths\":".length, end)
            Regex("-?[0-9][0-9.eE+-]*").findAll(section).forEach { texts.add(it.value) }
            from = end
        }
        return texts
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
