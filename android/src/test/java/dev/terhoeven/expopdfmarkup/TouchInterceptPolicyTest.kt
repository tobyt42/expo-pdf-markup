package dev.terhoeven.expopdfmarkup

import android.view.MotionEvent
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class TouchInterceptPolicyTest {

    @Test
    fun testRequestsDisallowOnDown() {
        assertEquals(true, TouchInterceptPolicy.disallowInterceptFor(MotionEvent.ACTION_DOWN))
    }

    @Test
    fun testReleasesDisallowOnUp() {
        assertEquals(false, TouchInterceptPolicy.disallowInterceptFor(MotionEvent.ACTION_UP))
    }

    @Test
    fun testReleasesDisallowOnCancel() {
        assertEquals(false, TouchInterceptPolicy.disallowInterceptFor(MotionEvent.ACTION_CANCEL))
    }

    @Test
    fun testKeepsStateOnMove() {
        assertNull(TouchInterceptPolicy.disallowInterceptFor(MotionEvent.ACTION_MOVE))
    }

    @Test
    fun testKeepsStateOnPointerDown() {
        // Second finger of a pinch zoom must not change the hold.
        assertNull(TouchInterceptPolicy.disallowInterceptFor(MotionEvent.ACTION_POINTER_DOWN))
    }

    @Test
    fun testKeepsStateOnPointerUp() {
        // Lifting one of two fingers mid-pinch must not release the hold.
        assertNull(TouchInterceptPolicy.disallowInterceptFor(MotionEvent.ACTION_POINTER_UP))
    }
}
