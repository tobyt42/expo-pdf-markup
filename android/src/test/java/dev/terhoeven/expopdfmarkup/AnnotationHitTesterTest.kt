package dev.terhoeven.expopdfmarkup

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class AnnotationHitTesterTest {

    // MARK: - Ink hit testing

    @Test
    fun testHitOnInkPath() {
        val ink = AnnotationModel(
            id = "ink-1",
            type = "ink",
            page = 0,
            color = "#000000",
            lineWidth = 4f,
            paths = listOf(
                listOf(
                    AnnotationPoint(0f, 0f),
                    AnnotationPoint(100f, 0f)
                )
            )
        )
        // Tap near the line (within tolerance)
        val result = AnnotationHitTester.hitTest(AnnotationPoint(50f, 3f), listOf(ink), 0)
        assertNotNull(result)
        assertEquals("ink-1", result!!.id)
    }

    @Test
    fun testMissInkPath() {
        val ink = AnnotationModel(
            id = "ink-1",
            type = "ink",
            page = 0,
            color = "#000000",
            lineWidth = 2f,
            paths = listOf(
                listOf(
                    AnnotationPoint(0f, 0f),
                    AnnotationPoint(100f, 0f)
                )
            )
        )
        // Tap far from the line
        val result = AnnotationHitTester.hitTest(AnnotationPoint(50f, 50f), listOf(ink), 0)
        assertNull(result)
    }

    @Test
    fun testHitOnSinglePointInk() {
        val ink = AnnotationModel(
            id = "dot",
            type = "ink",
            page = 0,
            color = "#000000",
            lineWidth = 5f,
            paths = listOf(listOf(AnnotationPoint(50f, 50f)))
        )
        val result = AnnotationHitTester.hitTest(AnnotationPoint(53f, 50f), listOf(ink), 0)
        assertNotNull(result)
    }

    // MARK: - Bounds-based hit testing

    @Test
    fun testHitInsideHighlight() {
        val hl = AnnotationModel(
            id = "hl-1",
            type = "highlight",
            page = 0,
            color = "#FFFF00",
            bounds = AnnotationBounds(100f, 200f, 300f, 20f)
        )
        val result = AnnotationHitTester.hitTest(AnnotationPoint(200f, 210f), listOf(hl), 0)
        assertNotNull(result)
        assertEquals("hl-1", result!!.id)
    }

    @Test
    fun testMissOutsideHighlight() {
        val hl = AnnotationModel(
            id = "hl-1",
            type = "highlight",
            page = 0,
            color = "#FFFF00",
            bounds = AnnotationBounds(100f, 200f, 300f, 20f)
        )
        val result = AnnotationHitTester.hitTest(AnnotationPoint(50f, 210f), listOf(hl), 0)
        assertNull(result)
    }

    // MARK: - Page filtering

    @Test
    fun testHitTestFiltersByPage() {
        val ann = AnnotationModel(
            id = "a",
            type = "highlight",
            page = 1,
            color = "#000000",
            bounds = AnnotationBounds(0f, 0f, 100f, 100f)
        )
        // Tap on page 0 should miss annotation on page 1
        assertNull(AnnotationHitTester.hitTest(AnnotationPoint(50f, 50f), listOf(ann), 0))
        // Tap on page 1 should hit
        assertNotNull(AnnotationHitTester.hitTest(AnnotationPoint(50f, 50f), listOf(ann), 1))
    }

    // MARK: - Topmost annotation wins

    @Test
    fun testOverlappingAnnotationsReturnsTopmost() {
        val bottom = AnnotationModel(
            id = "bottom",
            type = "highlight",
            page = 0,
            color = "#FF0000",
            bounds = AnnotationBounds(0f, 0f, 200f, 200f)
        )
        val top = AnnotationModel(
            id = "top",
            type = "highlight",
            page = 0,
            color = "#00FF00",
            bounds = AnnotationBounds(50f, 50f, 100f, 100f)
        )
        // top is last in list = topmost
        val result = AnnotationHitTester.hitTest(AnnotationPoint(75f, 75f), listOf(bottom, top), 0)
        assertNotNull(result)
        assertEquals("top", result!!.id)
    }

    // MARK: - Distance to segment

    @Test
    fun testDistanceToSegmentOnLine() {
        val dist = AnnotationHitTester.distanceToSegment(
            AnnotationPoint(5f, 0f),
            AnnotationPoint(0f, 0f),
            AnnotationPoint(10f, 0f)
        )
        assertEquals(0f, dist, 0.001f)
    }

    @Test
    fun testDistanceToSegmentPerpendicular() {
        val dist = AnnotationHitTester.distanceToSegment(
            AnnotationPoint(5f, 5f),
            AnnotationPoint(0f, 0f),
            AnnotationPoint(10f, 0f)
        )
        assertEquals(5f, dist, 0.001f)
    }

    @Test
    fun testDistanceToSegmentPastEndpoint() {
        val dist = AnnotationHitTester.distanceToSegment(
            AnnotationPoint(15f, 0f),
            AnnotationPoint(0f, 0f),
            AnnotationPoint(10f, 0f)
        )
        assertEquals(5f, dist, 0.001f)
    }

    @Test
    fun testDistanceToZeroLengthSegment() {
        val dist = AnnotationHitTester.distanceToSegment(
            AnnotationPoint(3f, 4f),
            AnnotationPoint(0f, 0f),
            AnnotationPoint(0f, 0f)
        )
        assertEquals(5f, dist, 0.001f)
    }
}
