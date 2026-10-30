package dev.terhoeven.expopdfmarkup

import android.view.KeyEvent

/**
 * Turn decisions for book mode. Every caller is book mode only, so nothing
 * here takes the display mode.
 */
object BookTurnPolicy {
    /** Scales within this of fit (1.0) count as "at fit", absorbing pinch rounding. */
    private const val FIT_TOLERANCE = 0.01f

    private const val EDGE_ZONE_FRACTION = 0.25f
    private const val MIN_EDGE_ZONE_DP = 44f

    /** Share of the view's width a slow swipe has to travel to turn the page. */
    private const val SWIPE_TURN_FRACTION = 0.25f

    enum class SwipeAction { TURN, PAN }

    /** Direction of a page turn. [delta] is the change in page index. */
    enum class Direction(val delta: Int) { NEXT(1), PREVIOUS(-1) }

    /**
     * Width of each edge tap zone: the outer quarter of the view, at least
     * 44 dp, but never more than half the view so the zones can't overlap.
     */
    fun edgeZoneWidth(viewWidth: Float, density: Float): Float =
        maxOf(viewWidth * EDGE_ZONE_FRACTION, MIN_EDGE_ZONE_DP * density)
            .coerceAtMost(viewWidth / 2f)

    /** The turn an edge tap at [x] asks for, or null for no turn. */
    fun edgeTapTurnFor(
        annotationMode: String,
        scale: Float,
        x: Float,
        viewWidth: Float,
        density: Float
    ): Direction? {
        if (!touchCanTurn(annotationMode, scale) || viewWidth <= 0f) return null
        val zone = edgeZoneWidth(viewWidth, density)
        return when {
            x < zone -> Direction.PREVIOUS
            x > viewWidth - zone -> Direction.NEXT
            else -> null
        }
    }

    /**
     * Whether a double-tap at [x] zooms. Where an edge tap would turn, the
     * first tap of the pair has already turned the page, so the second is
     * swallowed: a double-tap zooms only in the middle region, or anywhere
     * while edge taps can't turn (zoomed in or with a markup tool active).
     */
    fun doubleTapZooms(
        annotationMode: String,
        scale: Float,
        x: Float,
        viewWidth: Float,
        density: Float
    ): Boolean = edgeTapTurnFor(annotationMode, scale, x, viewWidth, density) == null

    /**
     * Swipes and edge taps turn the page only with no markup tool active,
     * while the page is not zoomed in beyond fit (scale 1).
     */
    fun touchCanTurn(annotationMode: String, scale: Float): Boolean =
        annotationMode == "none" && scale <= 1f + FIT_TOLERANCE

    /**
     * The turn a released horizontal swipe asks for, or null to settle back.
     * [dragX] is the finger's total horizontal travel (negative = leftwards).
     * Leftwards always means next, whatever the layout direction. A fast
     * fling turns in its own direction unless it flicks back against the
     * drag; a slow release turns once the drag passes a quarter of the view.
     */
    fun swipeReleaseTurnFor(
        dragX: Float,
        velocityX: Float,
        viewWidth: Float,
        flingVelocity: Float
    ): Direction? {
        val fromDrag = when {
            dragX <= -viewWidth * SWIPE_TURN_FRACTION -> Direction.NEXT
            dragX >= viewWidth * SWIPE_TURN_FRACTION -> Direction.PREVIOUS
            else -> null
        }
        if (kotlin.math.abs(velocityX) < flingVelocity) return fromDrag
        val fromFling = if (velocityX < 0f) Direction.NEXT else Direction.PREVIOUS
        val dragOpposes = (fromFling == Direction.NEXT && dragX > 0f) ||
            (fromFling == Direction.PREVIOUS && dragX < 0f)
        return if (dragOpposes) null else fromFling
    }

    /**
     * The turn a hardware key (keyboard or page-turner pedal) asks for, or
     * null to leave the key alone. Right, Down and Page Down go forward; Left,
     * Up and Page Up go back; Space isn't mapped. Keys turn whatever the zoom
     * or markup mode, but never while a text input has focus, and never with
     * a modifier held.
     */
    fun keyTurnFor(keyCode: Int, textInputHasFocus: Boolean, hasModifiers: Boolean): Direction? {
        if (textInputHasFocus || hasModifiers) return null
        return when (keyCode) {
            KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.KEYCODE_DPAD_DOWN, KeyEvent.KEYCODE_PAGE_DOWN ->
                Direction.NEXT

            KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_PAGE_UP ->
                Direction.PREVIOUS

            else -> null
        }
    }

    fun swipeActionFor(annotationMode: String, scale: Float): SwipeAction =
        if (touchCanTurn(annotationMode, scale)) SwipeAction.TURN else SwipeAction.PAN
}
