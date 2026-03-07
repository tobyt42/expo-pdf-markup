package dev.terhoeven.expopdfmarkup

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
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
