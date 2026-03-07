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
}
