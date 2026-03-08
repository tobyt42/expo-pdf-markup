package dev.terhoeven.expopdfmarkup

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AnnotationSerializerTest {

    // MARK: - Round-trip serialization

    @Test
    fun testInkRoundTrip() {
        val model = AnnotationModel(
            id = "ink-1",
            type = "ink",
            page = 0,
            color = "#FF0000",
            lineWidth = 3f,
            paths = listOf(
                listOf(
                    AnnotationPoint(10f, 20f),
                    AnnotationPoint(30f, 40f),
                    AnnotationPoint(50f, 60f)
                )
            ),
            createdAt = 1700000000.0
        )
        val data = AnnotationsData(version = 1, annotations = listOf(model))
        val json = AnnotationSerializer.serialize(data)
        val result = AnnotationSerializer.deserialize(json)

        assertNotNull(result)
        assertEquals(1, result!!.annotations.size)
        val a = result.annotations[0]
        assertEquals("ink-1", a.id)
        assertEquals("ink", a.type)
        assertEquals(0, a.page)
        assertEquals("#FF0000", a.color)
        assertEquals(3f, a.lineWidth)
        assertEquals(1, a.paths!!.size)
        assertEquals(3, a.paths!![0].size)
        assertEquals(10f, a.paths!![0][0].x)
        assertEquals(20f, a.paths!![0][0].y)
        assertEquals(1700000000.0, a.createdAt!!, 0.001)
    }

    @Test
    fun testHighlightRoundTrip() {
        val model = AnnotationModel(
            id = "hl-1",
            type = "highlight",
            page = 1,
            color = "#FFFF00",
            alpha = 0.5f,
            bounds = AnnotationBounds(100f, 200f, 300f, 20f)
        )
        val data = AnnotationsData(annotations = listOf(model))
        val json = AnnotationSerializer.serialize(data)
        val result = AnnotationSerializer.deserialize(json)

        assertNotNull(result)
        val a = result!!.annotations[0]
        assertEquals("highlight", a.type)
        assertEquals(0.5f, a.alpha!!, 0.01f)
        assertEquals(100f, a.bounds!!.x)
        assertEquals(200f, a.bounds!!.y)
        assertEquals(300f, a.bounds!!.width)
        assertEquals(20f, a.bounds!!.height)
    }

    @Test
    fun testUnderlineRoundTrip() {
        val model = AnnotationModel(
            id = "ul-1",
            type = "underline",
            page = 2,
            color = "#0000FF",
            bounds = AnnotationBounds(50f, 100f, 200f, 15f)
        )
        val data = AnnotationsData(annotations = listOf(model))
        val json = AnnotationSerializer.serialize(data)
        val result = AnnotationSerializer.deserialize(json)

        assertNotNull(result)
        assertEquals("underline", result!!.annotations[0].type)
        assertEquals(50f, result.annotations[0].bounds!!.x)
    }

    @Test
    fun testFreeTextRoundTrip() {
        val model = AnnotationModel(
            id = "ft-1",
            type = "freeText",
            page = 0,
            color = "#000000",
            bounds = AnnotationBounds(10f, 20f, 100f, 30f),
            contents = "Hello World",
            fontSize = 16f
        )
        val data = AnnotationsData(annotations = listOf(model))
        val json = AnnotationSerializer.serialize(data)
        val result = AnnotationSerializer.deserialize(json)

        assertNotNull(result)
        val a = result!!.annotations[0]
        assertEquals("freeText", a.type)
        assertEquals("Hello World", a.contents)
        assertEquals(16f, a.fontSize)
    }

    // MARK: - Edge cases

    @Test
    fun testMalformedJsonReturnsNull() {
        assertNull(AnnotationSerializer.deserialize("not json"))
        assertNull(AnnotationSerializer.deserialize("{broken"))
        assertNull(AnnotationSerializer.deserialize(""))
    }

    @Test
    fun testEmptyAnnotations() {
        val result = AnnotationSerializer.deserialize("""{"version":1,"annotations":[]}""")
        assertNotNull(result)
        assertTrue(result!!.annotations.isEmpty())
    }

    @Test
    fun testMissingOptionalFields() {
        val json =
            """{"version":1,"annotations":[{"id":"a","type":"ink","page":0,"color":"#000"}]}"""
        val result = AnnotationSerializer.deserialize(json)
        assertNotNull(result)
        val a = result!!.annotations[0]
        assertNull(a.lineWidth)
        assertNull(a.alpha)
        assertNull(a.paths)
        assertNull(a.bounds)
        assertNull(a.contents)
        assertNull(a.fontSize)
        assertNull(a.createdAt)
    }

    @Test
    fun testMissingRequiredFieldsSkipsAnnotation() {
        // Missing id
        val json1 = """{"version":1,"annotations":[{"type":"ink","page":0,"color":"#000"}]}"""
        assertEquals(0, AnnotationSerializer.deserialize(json1)!!.annotations.size)

        // Missing type
        val json2 = """{"version":1,"annotations":[{"id":"a","page":0,"color":"#000"}]}"""
        assertEquals(0, AnnotationSerializer.deserialize(json2)!!.annotations.size)
    }

    @Test
    fun testMissingAnnotationsArrayReturnsEmptyList() {
        val result = AnnotationSerializer.deserialize("""{"version":1}""")
        assertNotNull(result)
        assertTrue(result!!.annotations.isEmpty())
    }

    // MARK: - Color parsing

    @Test
    fun testColorFromHex6Char() {
        val color = AnnotationSerializer.colorFromHex("#FF0000")
        assertEquals(0xFFFF0000.toInt(), color)
    }

    @Test
    fun testColorFromHex6CharNoHash() {
        val color = AnnotationSerializer.colorFromHex("00FF00")
        assertEquals(0xFF00FF00.toInt(), color)
    }

    @Test
    fun testColorFromHex8CharWithAlpha() {
        val color = AnnotationSerializer.colorFromHex("#FF000080")
        // R=FF, G=00, B=00, A=80
        assertEquals(0x80FF0000.toInt(), color)
    }

    @Test
    fun testColorFromHexInvalidLength() {
        // Falls back to opaque black
        val color = AnnotationSerializer.colorFromHex("#FFF")
        assertEquals(0xFF000000.toInt(), color)
    }

    @Test
    fun testHexFromColorRoundTrip() {
        val original = 0xFFFF8800.toInt()
        val hex = AnnotationSerializer.hexFromColor(original)
        assertEquals("#FF8800", hex)
        val back = AnnotationSerializer.colorFromHex(hex)
        // Alpha gets set to FF by colorFromHex for 6-char
        assertEquals(0xFFFF8800.toInt(), back)
    }

    @Test
    fun testHexFromColorBlack() {
        assertEquals("#000000", AnnotationSerializer.hexFromColor(0xFF000000.toInt()))
    }

    @Test
    fun testHexFromColorWhite() {
        assertEquals("#FFFFFF", AnnotationSerializer.hexFromColor(0xFFFFFFFF.toInt()))
    }

    // MARK: - Multiple annotations

    @Test
    fun testMultipleAnnotationsRoundTrip() {
        val annotations = listOf(
            AnnotationModel(id = "1", type = "ink", page = 0, color = "#FF0000"),
            AnnotationModel(id = "2", type = "highlight", page = 1, color = "#00FF00"),
            AnnotationModel(id = "3", type = "freeText", page = 0, color = "#0000FF")
        )
        val data = AnnotationsData(annotations = annotations)
        val json = AnnotationSerializer.serialize(data)
        val result = AnnotationSerializer.deserialize(json)

        assertNotNull(result)
        assertEquals(3, result!!.annotations.size)
        assertEquals("1", result.annotations[0].id)
        assertEquals("2", result.annotations[1].id)
        assertEquals("3", result.annotations[2].id)
    }
}
