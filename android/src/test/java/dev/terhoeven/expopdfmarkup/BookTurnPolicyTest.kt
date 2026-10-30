package dev.terhoeven.expopdfmarkup

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class BookTurnPolicyTest {

    @Test
    fun testSwipeTurnsInBookModeAtFitWithNoTool() {
        assertEquals(
            BookTurnPolicy.SwipeAction.TURN,
            BookTurnPolicy.swipeActionFor(annotationMode = "none", scale = 1f)
        )
    }

    @Test
    fun testSwipePansWhenZoomedBeyondFit() {
        assertEquals(
            BookTurnPolicy.SwipeAction.PAN,
            BookTurnPolicy.swipeActionFor(annotationMode = "none", scale = 1.5f)
        )
    }

    @Test
    fun testSwipeNeverTurnsWithAnyMarkupToolActive() {
        for (tool in listOf("ink", "highlight", "underline", "text", "stamp", "eraser", "move")) {
            assertEquals(
                "tool $tool",
                BookTurnPolicy.SwipeAction.PAN,
                BookTurnPolicy.swipeActionFor(annotationMode = tool, scale = 1f)
            )
        }
    }

    // MARK: - Edge taps

    private fun tap(
        x: Float,
        viewWidth: Float = 1000f,
        density: Float = 1f,
        annotationMode: String = "none",
        scale: Float = 1f
    ) = BookTurnPolicy.edgeTapTurnFor(annotationMode, scale, x, viewWidth, density)

    @Test
    fun testTapInRightQuarterTurnsToNextPage() {
        assertEquals(BookTurnPolicy.Direction.NEXT, tap(x = 760f))
        assertEquals(BookTurnPolicy.Direction.NEXT, tap(x = 999f))
    }

    @Test
    fun testTapInLeftQuarterTurnsToPreviousPage() {
        assertEquals(BookTurnPolicy.Direction.PREVIOUS, tap(x = 0f))
        assertEquals(BookTurnPolicy.Direction.PREVIOUS, tap(x = 240f))
    }

    @Test
    fun testTapInMiddleDoesNothing() {
        assertNull(tap(x = 260f))
        assertNull(tap(x = 500f))
        assertNull(tap(x = 740f))
    }

    @Test
    fun testEdgeZoneIsAtLeast44Dp() {
        // 25% of 300 px is 75 px, but 44 dp at density 3 is 132 px.
        assertEquals(
            BookTurnPolicy.Direction.PREVIOUS,
            tap(x = 120f, viewWidth = 300f, density = 3f)
        )
        assertEquals(BookTurnPolicy.Direction.NEXT, tap(x = 180f, viewWidth = 300f, density = 3f))
    }

    @Test
    fun testEdgeZonesNeverOverlapOnVeryNarrowViews() {
        // 44 dp would be wider than half of 80 px, so each zone is capped at half.
        assertEquals(BookTurnPolicy.Direction.PREVIOUS, tap(x = 39f, viewWidth = 80f))
        assertEquals(BookTurnPolicy.Direction.NEXT, tap(x = 41f, viewWidth = 80f))
    }

    @Test
    fun testEdgeTapDoesNotTurnWhenZoomedIn() {
        assertNull(tap(x = 900f, scale = 2f))
        assertNull(tap(x = 100f, scale = 2f))
    }

    @Test
    fun testEdgeTapDoesNotTurnWithMarkupToolActive() {
        assertNull(tap(x = 900f, annotationMode = "ink"))
        assertNull(tap(x = 100f, annotationMode = "text"))
    }

    // MARK: - Double taps

    private fun doubleTapZooms(x: Float, annotationMode: String = "none", scale: Float = 1f) =
        BookTurnPolicy.doubleTapZooms(annotationMode, scale, x, viewWidth = 1000f, density = 1f)

    @Test
    fun testDoubleTapOnAnEdgeDoesNotZoom() {
        // The first tap already turned the page; the second is swallowed, as on iOS.
        assertFalse(doubleTapZooms(x = 900f))
        assertFalse(doubleTapZooms(x = 100f))
    }

    @Test
    fun testDoubleTapInTheMiddleZooms() {
        assertTrue(doubleTapZooms(x = 500f))
    }

    @Test
    fun testDoubleTapOnAnEdgeZoomsWhenEdgeTapsCannotTurn() {
        // Zoomed in, edges don't turn, so a double-tap anywhere zooms back out.
        assertTrue(doubleTapZooms(x = 900f, scale = 2f))
        assertTrue(doubleTapZooms(x = 900f, annotationMode = "ink"))
    }

    // MARK: - Swipe release

    private fun release(dragX: Float, velocityX: Float = 0f) = BookTurnPolicy.swipeReleaseTurnFor(
        dragX = dragX,
        velocityX = velocityX,
        viewWidth = 1000f,
        flingVelocity = 1000f
    )

    @Test
    fun testLongDragLeftTurnsToNextPage() {
        // Swipe left always means next; there is no layout direction input.
        assertEquals(BookTurnPolicy.Direction.NEXT, release(dragX = -300f))
    }

    @Test
    fun testLongDragRightTurnsToPreviousPage() {
        assertEquals(BookTurnPolicy.Direction.PREVIOUS, release(dragX = 300f))
    }

    @Test
    fun testShortSlowDragSettlesBack() {
        assertNull(release(dragX = -100f))
        assertNull(release(dragX = 100f))
    }

    @Test
    fun testShortFastFlingTurns() {
        assertEquals(BookTurnPolicy.Direction.NEXT, release(dragX = -50f, velocityX = -2000f))
        assertEquals(BookTurnPolicy.Direction.PREVIOUS, release(dragX = 50f, velocityX = 2000f))
    }

    @Test
    fun testFlingBackAgainstTheDragSettlesBack() {
        assertNull(release(dragX = -300f, velocityX = 2000f))
        assertNull(release(dragX = 300f, velocityX = -2000f))
    }
}
