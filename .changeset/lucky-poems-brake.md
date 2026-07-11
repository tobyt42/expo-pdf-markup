---
"@tobyt/expo-pdf-markup": patch
---

Android: fix touch-interception lifecycle in the PDF view. The view previously called `requestDisallowInterceptTouchEvent(true)` on every touch event and never released it, and in-progress gestures were never reset when interrupted. This could leave stale touch state on ancestor views shared with sibling screens (e.g. list rows behind the PDF screen becoming unresponsive to taps after navigating back, especially after locking/unlocking the device), and caused unnecessary gesture-handler contention while scrolling.

Now the parent intercept hold is requested on `ACTION_DOWN` and released on the final `ACTION_UP`/`ACTION_CANCEL` (held across multi-touch pinch), and all in-progress gestures (ink stroke, highlight/underline drag, annotation move, fling) are cancelled and the hold released when the window loses focus (device lock) or the view detaches. Note: an ink stroke interrupted by a device lock is discarded rather than committed.
