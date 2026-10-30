---
'@tobyt/expo-pdf-markup': minor
---

Add book mode. `ExpoPdfMarkupView` takes a new `displayMode` prop, `'continuous'` (the default) or `'book'`. Book mode shows one page at a time, fitted to the view, and turns pages sideways with a slide animation: swipe horizontally, tap the outer quarter of the view on either side, or press the arrow or Page Up / Page Down keys, which is what Bluetooth page-turner pedals send. Pinch to zoom still works, and while the page is zoomed in a swipe pans instead of turning. Markup tools keep working in book mode and take priority over swipes and taps, while hardware keys still turn the page. `page` and `onPageChanged` behave the same in both modes, and changing `displayMode` or rotating keeps the current page. Leaving `displayMode` out keeps today's continuous behaviour. The library adds no user-facing text: page indicators and announcements are up to your app. Book mode needs a new native build.
