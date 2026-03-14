package dev.terhoeven.expopdfmarkup

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

class AnnotationGeometryTest {

    @Test
    fun testOutlineBoundsReturnsStoredBounds() {
        val annotation = AnnotationModel(
            id = "highlight",
            type = "highlight",
            page = 0,
            color = "#FFFF00",
            bounds = AnnotationBounds(50f, 50f, 100f, 20f)
        )

        val result = AnnotationGeometry.outlineBounds(annotation)

        assertEquals(50f, result!!.x, 0.001f)
        assertEquals(50f, result.y, 0.001f)
        assertEquals(100f, result.width, 0.001f)
        assertEquals(20f, result.height, 0.001f)
    }

    @Test
    fun testOutlineBoundsComputesInkBounds() {
        val annotation = AnnotationModel(
            id = "ink",
            type = "ink",
            page = 0,
            color = "#000000",
            lineWidth = 2f,
            paths = listOf(listOf(AnnotationPoint(0f, 0f), AnnotationPoint(100f, 0f)))
        )

        val result = AnnotationGeometry.outlineBounds(annotation)

        assertNotNull(result)
        assertEquals(-10f, result!!.x, 0.001f)
        assertEquals(-10f, result.y, 0.001f)
        assertEquals(120f, result.width, 0.001f)
        assertEquals(20f, result.height, 0.001f)
    }

    @Test
    fun testTranslateMovesAllInkPoints() {
        val annotation = AnnotationModel(
            id = "ink",
            type = "ink",
            page = 0,
            color = "#000000",
            paths = listOf(listOf(AnnotationPoint(1f, 2f), AnnotationPoint(3f, 4f)))
        )

        val result = AnnotationGeometry.translate(annotation, 5f, 7f)

        assertEquals(6f, result.paths!![0][0].x, 0.001f)
        assertEquals(9f, result.paths!![0][0].y, 0.001f)
        assertEquals(8f, result.paths!![0][1].x, 0.001f)
        assertEquals(11f, result.paths!![0][1].y, 0.001f)
    }

    @Test
    fun testClampTranslationKeepsAnnotationOnPage() {
        val annotation = AnnotationModel(
            id = "highlight",
            type = "highlight",
            page = 0,
            color = "#FFFF00",
            bounds = AnnotationBounds(50f, 50f, 100f, 20f)
        )

        val result = AnnotationGeometry.clampTranslation(annotation, -100f, 100f, 200f, 100f)

        assertEquals(-50f, result.x, 0.001f)
        assertEquals(30f, result.y, 0.001f)
    }
}
