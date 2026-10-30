package dev.terhoeven.expopdfmarkup

import android.view.KeyEvent

object BookTurnPolicy {
    /** Scales within this of fit (1.0) count as "at fit", absorbing pinch rounding. */
    private const val FIT_TOLERANCE = 0.01f

    private const val EDGE_ZONE_FRACTION = 0.25f
    private const val MIN_EDGE_ZONE_DP = 44f

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
        isBookMode: Boolean,
        annotationMode: String,
        scale: Float,
        x: Float,
        viewWidth: Float,
        density: Float
    ): Direction? {
        if (!touchCanTurn(isBookMode, annotationMode, scale) || viewWidth <= 0f) return null
        val zone = edgeZoneWidth(viewWidth, density)
        return when {
            x < zone -> Direction.PREVIOUS
            x > viewWidth - zone -> Direction.NEXT
            else -> null
        }
    }

    /**
     * Swipes and edge taps turn the page only in book mode, with no markup tool
     * active, while the page is not zoomed in beyond fit (scale 1).
     */
    fun touchCanTurn(isBookMode: Boolean, annotationMode: String, scale: Float): Boolean =
        isBookMode && annotationMode == "none" && scale <= 1f + FIT_TOLERANCE

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
            dragX <= -viewWidth * EDGE_ZONE_FRACTION -> Direction.NEXT
            dragX >= viewWidth * EDGE_ZONE_FRACTION -> Direction.PREVIOUS
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
     * Up and Page Up go back; Space isn't mapped. Keys turn in book mode
     * whatever the zoom or markup mode, but never while a text input has
     * focus, and never with a modifier held.
     */
    fun keyTurnFor(
        keyCode: Int,
        isBookMode: Boolean,
        textInputHasFocus: Boolean,
        hasModifiers: Boolean
    ): Direction? {
        if (!isBookMode || textInputHasFocus || hasModifiers) return null
        return when (keyCode) {
            KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.KEYCODE_DPAD_DOWN, KeyEvent.KEYCODE_PAGE_DOWN ->
                Direction.NEXT

            KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_PAGE_UP ->
                Direction.PREVIOUS

            else -> null
        }
    }

    fun swipeActionFor(isBookMode: Boolean, annotationMode: String, scale: Float): SwipeAction =
        if (touchCanTurn(isBookMode, annotationMode, scale)) SwipeAction.TURN else SwipeAction.PAN
}
