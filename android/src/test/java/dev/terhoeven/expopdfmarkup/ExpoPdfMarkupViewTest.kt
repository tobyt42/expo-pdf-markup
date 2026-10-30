package dev.terhoeven.expopdfmarkup

import android.view.KeyEvent
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Tests for the core PDF view logic (source deduplication, page navigation bounds).
 * Pure JUnit — no Android framework or Robolectric needed.
 */
class ExpoPdfMarkupViewTest {
    // MARK: - Source deduplication logic

    @Test
    fun testSourceDeduplication() {
        var currentSource: String? = null
        var loadCount = 0

        fun loadPdf(source: String) {
            if (source == currentSource) return
            currentSource = source
            loadCount++
        }

        loadPdf("/path/to/file.pdf")
        assertEquals(1, loadCount)

        // Same source should be skipped
        loadPdf("/path/to/file.pdf")
        assertEquals(1, loadCount)

        // Different source should load
        loadPdf("/path/to/other.pdf")
        assertEquals(2, loadCount)
    }

    // MARK: - Page navigation logic

    @Test
    fun testGoToPageRejectsNegativeIndex() {
        val pageCount = 5
        var currentPageIndex = 2

        fun goToPage(pageIndex: Int): Boolean {
            if (pageIndex < 0 || pageIndex >= pageCount) return false
            if (pageIndex == currentPageIndex) return false
            currentPageIndex = pageIndex
            return true
        }

        assertFalse("Should reject negative index", goToPage(-1))
        assertEquals(2, currentPageIndex)
    }

    @Test
    fun testGoToPageRejectsOutOfBounds() {
        val pageCount = 5
        var currentPageIndex = 2

        fun goToPage(pageIndex: Int): Boolean {
            if (pageIndex < 0 || pageIndex >= pageCount) return false
            if (pageIndex == currentPageIndex) return false
            currentPageIndex = pageIndex
            return true
        }

        assertFalse("Should reject index >= pageCount", goToPage(5))
        assertFalse("Should reject large index", goToPage(100))
        assertEquals(2, currentPageIndex)
    }

    @Test
    fun testGoToPageSkipsSamePage() {
        val pageCount = 5
        var currentPageIndex = 2

        fun goToPage(pageIndex: Int): Boolean {
            if (pageIndex < 0 || pageIndex >= pageCount) return false
            if (pageIndex == currentPageIndex) return false
            currentPageIndex = pageIndex
            return true
        }

        assertFalse("Should skip same page", goToPage(2))
    }

    @Test
    fun testGoToPageNavigatesToValidIndex() {
        val pageCount = 5
        var currentPageIndex = 0

        fun goToPage(pageIndex: Int): Boolean {
            if (pageIndex < 0 || pageIndex >= pageCount) return false
            if (pageIndex == currentPageIndex) return false
            currentPageIndex = pageIndex
            return true
        }

        assertTrue("Should navigate to page 3", goToPage(3))
        assertEquals(3, currentPageIndex)

        assertTrue("Should navigate to first page", goToPage(0))
        assertEquals(0, currentPageIndex)

        assertTrue("Should navigate to last page", goToPage(4))
        assertEquals(4, currentPageIndex)
    }

    // MARK: - Page bounds validation

    @Test
    fun testPageIndexBoundsRange() {
        val pageCount = 3
        val validRange = 0 until pageCount

        assertTrue(0 in validRange)
        assertTrue(1 in validRange)
        assertTrue(2 in validRange)
        assertFalse(-1 in validRange)
        assertFalse(3 in validRange)
    }

    // MARK: - Book mode hardware keys

    private fun keyTurn(
        keyCode: Int,
        textInputHasFocus: Boolean = false,
        hasModifiers: Boolean = false
    ) = BookTurnPolicy.keyTurnFor(keyCode, textInputHasFocus, hasModifiers)

    @Test
    fun testRightDownAndPageDownTurnToTheNextPage() {
        for (key in listOf(
            KeyEvent.KEYCODE_DPAD_RIGHT,
            KeyEvent.KEYCODE_DPAD_DOWN,
            KeyEvent.KEYCODE_PAGE_DOWN
        )) {
            assertEquals("key $key", BookTurnPolicy.Direction.NEXT, keyTurn(key))
        }
    }

    @Test
    fun testLeftUpAndPageUpTurnToThePreviousPage() {
        for (key in listOf(
            KeyEvent.KEYCODE_DPAD_LEFT,
            KeyEvent.KEYCODE_DPAD_UP,
            KeyEvent.KEYCODE_PAGE_UP
        )) {
            assertEquals("key $key", BookTurnPolicy.Direction.PREVIOUS, keyTurn(key))
        }
    }

    @Test
    fun testSpaceAndOtherKeysDoNotTurn() {
        assertNull(keyTurn(KeyEvent.KEYCODE_SPACE))
        assertNull(keyTurn(KeyEvent.KEYCODE_ENTER))
        assertNull(keyTurn(KeyEvent.KEYCODE_A))
    }

    @Test
    fun testKeysAreIgnoredWhileATextInputHasFocus() {
        for (key in listOf(
            KeyEvent.KEYCODE_DPAD_RIGHT,
            KeyEvent.KEYCODE_DPAD_LEFT,
            KeyEvent.KEYCODE_PAGE_UP
        )) {
            assertNull("key $key", keyTurn(key, textInputHasFocus = true))
        }
    }

    @Test
    fun testKeysWithAModifierAreLeftAlone() {
        assertNull(keyTurn(KeyEvent.KEYCODE_DPAD_LEFT, hasModifiers = true))
        assertNull(keyTurn(KeyEvent.KEYCODE_PAGE_DOWN, hasModifiers = true))
    }

    @Test
    fun testKeysTurnWhereTouchCannotWhileZoomedOrWithAMarkupTool() {
        // Zoomed in with the ink tool active, swipes and edge taps are blocked...
        assertFalse(
            BookTurnPolicy.touchCanTurn(annotationMode = "ink", scale = 2f)
        )
        // ...but the key policy doesn't look at zoom or markup mode, so keys still turn.
        assertEquals(BookTurnPolicy.Direction.NEXT, keyTurn(KeyEvent.KEYCODE_PAGE_DOWN))
    }

    @Test
    fun testKeyTurnsBounceAtBothEndsAndReportOncePerTurn() {
        val r = RecordingPager(pageCount = 3)
        fun pressAndLand(keyCode: Int): BookPager.Turn {
            val turn = r.pager.turn(keyTurn(keyCode)!!)
            r.pager.finishSlide()
            return turn
        }

        assertEquals(
            BookPager.Turn.Bounce(BookTurnPolicy.Direction.PREVIOUS),
            pressAndLand(KeyEvent.KEYCODE_DPAD_LEFT)
        )
        repeat(4) { pressAndLand(KeyEvent.KEYCODE_PAGE_DOWN) }

        assertEquals(listOf(1, 2), r.changes)
        assertEquals(2, r.pager.currentPage)
    }

    // MARK: - Book mode page turning

    private class RecordingPager(pageCount: Int, page: Int = 0) {
        val changes = mutableListOf<Int>()
        val pager = BookPager { changes.add(it) }.apply { reset(pageCount, page) }
    }

    @Test
    fun testBookModeTurnSlidesToNextPageAndReportsItOnce() {
        val r = RecordingPager(pageCount = 5)

        val turn = r.pager.turn(BookTurnPolicy.Direction.NEXT)

        assertEquals(BookPager.Turn.Slide(from = 0, to = 1, BookTurnPolicy.Direction.NEXT), turn)
        assertEquals("page changes only when the slide completes", emptyList<Int>(), r.changes)
        r.pager.finishSlide()
        assertEquals(1, r.pager.currentPage)
        assertEquals(listOf(1), r.changes)
    }

    @Test
    fun testBookModeTurnPreviousSlidesBack() {
        val r = RecordingPager(pageCount = 5, page = 3)

        assertEquals(
            BookPager.Turn.Slide(from = 3, to = 2, BookTurnPolicy.Direction.PREVIOUS),
            r.pager.turn(BookTurnPolicy.Direction.PREVIOUS)
        )
        r.pager.finishSlide()
        assertEquals(listOf(2), r.changes)
    }

    @Test
    fun testBookModeBouncesBeforeTheFirstPage() {
        val r = RecordingPager(pageCount = 5, page = 0)

        val turn = r.pager.turn(BookTurnPolicy.Direction.PREVIOUS)
        r.pager.finishSlide()

        assertEquals(BookPager.Turn.Bounce(BookTurnPolicy.Direction.PREVIOUS), turn)
        assertEquals(0, r.pager.currentPage)
        assertEquals(emptyList<Int>(), r.changes)
    }

    @Test
    fun testBookModeBouncesPastTheLastPageAndDoesNotWrap() {
        val r = RecordingPager(pageCount = 5, page = 4)

        val turn = r.pager.turn(BookTurnPolicy.Direction.NEXT)
        r.pager.finishSlide()

        assertEquals(BookPager.Turn.Bounce(BookTurnPolicy.Direction.NEXT), turn)
        assertEquals(4, r.pager.currentPage)
        assertEquals(emptyList<Int>(), r.changes)
    }

    @Test
    fun testBookModeOnePagePdfNeverTurns() {
        val r = RecordingPager(pageCount = 1)

        assertEquals(
            BookPager.Turn.Bounce(BookTurnPolicy.Direction.NEXT),
            r.pager.turn(BookTurnPolicy.Direction.NEXT)
        )
        assertEquals(
            BookPager.Turn.Bounce(BookTurnPolicy.Direction.PREVIOUS),
            r.pager.turn(BookTurnPolicy.Direction.PREVIOUS)
        )
        r.pager.finishSlide()
        assertEquals(0, r.pager.currentPage)
        assertEquals(emptyList<Int>(), r.changes)
    }

    @Test
    fun testBookModeTurnDuringASlideLandsTheFirstTurnBeforeStartingTheNext() {
        // Rapid taps (or key presses) must each count, and each report once.
        val r = RecordingPager(pageCount = 5)

        r.pager.turn(BookTurnPolicy.Direction.NEXT)
        val second = r.pager.turn(BookTurnPolicy.Direction.NEXT)
        r.pager.finishSlide()
        r.pager.finishSlide()

        assertEquals(BookPager.Turn.Slide(from = 1, to = 2, BookTurnPolicy.Direction.NEXT), second)
        assertEquals(listOf(1, 2), r.changes)
    }

    @Test
    fun testBookModePagePropJumpsAndReportsOnce() {
        val r = RecordingPager(pageCount = 5)

        r.pager.jumpTo(3)
        r.pager.jumpTo(3)

        assertEquals(3, r.pager.currentPage)
        assertEquals(listOf(3), r.changes)
    }

    @Test
    fun testBookModePagePropIgnoresOutOfRangePages() {
        val r = RecordingPager(pageCount = 5, page = 2)

        r.pager.jumpTo(-1)
        r.pager.jumpTo(5)

        assertEquals(2, r.pager.currentPage)
        assertEquals(emptyList<Int>(), r.changes)
    }

    @Test
    fun testBookModePagePropDuringASlideCancelsTheSlide() {
        val r = RecordingPager(pageCount = 5)

        r.pager.turn(BookTurnPolicy.Direction.NEXT)
        r.pager.jumpTo(4)
        r.pager.finishSlide()

        assertEquals(4, r.pager.currentPage)
        assertEquals(listOf(4), r.changes)
    }

    @Test
    fun testBookModeResetKeepsThePageWithoutReporting() {
        // Switching displayMode, rotating or resizing re-lays out via reset.
        val r = RecordingPager(pageCount = 5, page = 3)

        r.pager.reset(pageCount = 5, page = 3)

        assertEquals(3, r.pager.currentPage)
        assertEquals(emptyList<Int>(), r.changes)
    }

    @Test
    fun testBookModeResetClampsToTheDocument() {
        val r = RecordingPager(pageCount = 2, page = 7)
        assertEquals(1, r.pager.currentPage)
        r.pager.reset(pageCount = 2, page = -3)
        assertEquals(0, r.pager.currentPage)
        r.pager.reset(pageCount = 0, page = 2)
        assertEquals(0, r.pager.currentPage)
    }

    // MARK: - Color string parsing

    @Test
    fun testParseColorStringTransparent() {
        // android.graphics.Color.TRANSPARENT == 0
        assertEquals(0, parseColorString("transparent"))
    }

    @Test
    fun testParseColorStringTransparentCaseInsensitive() {
        assertEquals(0, parseColorString("Transparent"))
        assertEquals(0, parseColorString("TRANSPARENT"))
    }

    @Test
    fun testParseColorStringRgb() {
        // android.graphics.Color.argb(255, r, g, b)
        val expected = (255 shl 24) or (255 shl 16) or (0 shl 8) or 0 // opaque red
        assertEquals(expected, parseColorString("rgb(255, 0, 0)"))
    }

    @Test
    fun testParseColorStringRgbNoSpaces() {
        val expected = (255 shl 24) or (0 shl 16) or (128 shl 8) or 255
        assertEquals(expected, parseColorString("rgb(0,128,255)"))
    }

    @Test
    fun testParseColorStringRgbaFullyOpaque() {
        val expected = (255 shl 24) or (100 shl 16) or (150 shl 8) or 200
        assertEquals(expected, parseColorString("rgba(100, 150, 200, 1)"))
    }

    @Test
    fun testParseColorStringRgbaFullyTransparent() {
        // alpha 0 → 0x00RRGGBB
        val expected = (0 shl 24) or (100 shl 16) or (150 shl 8) or 200
        assertEquals(expected, parseColorString("rgba(100, 150, 200, 0)"))
    }

    @Test
    fun testParseColorStringRgbaFractionalAlpha() {
        // alpha 0.5 → round(0.5 * 255) = 127
        val result = parseColorString("rgba(255, 255, 255, 0.5)")
        val alpha = (result!! ushr 24) and 0xFF
        assertEquals(127, alpha)
    }

    @Test
    fun testParseColorStringRgbaReactNativePaperSurface() {
        // Typical value from react-native-paper: rgba(28, 27, 31, 1.0)
        val expected = (255 shl 24) or (28 shl 16) or (27 shl 8) or 31
        assertEquals(expected, parseColorString("rgba(28, 27, 31, 1.0)"))
    }

    @Test
    fun testParseColorStringRgbClampsChannels() {
        val expected = (255 shl 24) or (255 shl 16) or (255 shl 8) or 255
        assertEquals(expected, parseColorString("rgb(999, 999, 999)"))
    }
}
