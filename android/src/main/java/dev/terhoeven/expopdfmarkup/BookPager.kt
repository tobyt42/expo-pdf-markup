package dev.terhoeven.expopdfmarkup

/**
 * Which page book mode shows, and how a turn moves between pages. Pure Kotlin
 * so the turn rules can be tested in the JVM; the view animates whatever
 * [turn] returns and calls [finishSlide] when the slide has landed.
 */
class BookPager(private val onPageChanged: (page: Int) -> Unit) {
    sealed interface Turn {
        data class Slide(val from: Int, val to: Int, val direction: BookTurnPolicy.Direction) : Turn

        /** No page that way: nudge towards [direction] and spring back. Nothing wraps round. */
        data class Bounce(val direction: BookTurnPolicy.Direction) : Turn
    }

    var pageCount = 0
        private set
    var currentPage = 0
        private set

    private var inFlight: Turn.Slide? = null

    /** True while a slide has started but not landed. */
    val isSliding: Boolean get() = inFlight != null

    /**
     * Sets the document and page without reporting a change, clamping [page]
     * into the document. Used on load, mode switch, rotation and resize.
     */
    fun reset(pageCount: Int, page: Int) {
        inFlight = null
        this.pageCount = maxOf(0, pageCount)
        currentPage = page.coerceIn(0, maxOf(0, this.pageCount - 1))
    }

    /**
     * Starts a turn. A slide already in flight lands first, so rapid turns
     * each count and each report once. Returns [Turn.Bounce] at either end.
     */
    fun turn(direction: BookTurnPolicy.Direction): Turn {
        finishSlide()
        val target = currentPage + direction.delta
        if (target !in 0 until pageCount) return Turn.Bounce(direction)
        val slide = Turn.Slide(currentPage, target, direction)
        inFlight = slide
        return slide
    }

    /** Shows [page] straight away (the `page` prop), cancelling any slide. */
    fun jumpTo(page: Int): Boolean {
        if (page !in 0 until pageCount) return false
        inFlight = null
        if (page == currentPage) return false
        currentPage = page
        onPageChanged(page)
        return true
    }

    /** Lands the slide in flight, if any, and reports the new page. */
    fun finishSlide() {
        val slide = inFlight ?: return
        inFlight = null
        currentPage = slide.to
        onPageChanged(currentPage)
    }
}
