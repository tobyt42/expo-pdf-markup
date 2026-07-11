package dev.terhoeven.expopdfmarkup

import android.view.MotionEvent

/**
 * Decides whether the parent's touch interception should be disallowed for a
 * given masked motion action, or left unchanged (null).
 *
 * The disallow flag is held for the whole gesture: requested on the initial
 * ACTION_DOWN and released only on the final ACTION_UP or ACTION_CANCEL.
 * ACTION_POINTER_DOWN/ACTION_POINTER_UP (extra fingers during pinch zoom)
 * must not release it mid-gesture.
 */
object TouchInterceptPolicy {
    fun disallowInterceptFor(actionMasked: Int): Boolean? = when (actionMasked) {
        MotionEvent.ACTION_DOWN -> true
        MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> false
        else -> null
    }
}
