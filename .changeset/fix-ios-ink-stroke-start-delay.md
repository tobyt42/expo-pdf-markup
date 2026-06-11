---
"@tobyt/expo-pdf-markup": patch
---

Fix iOS ink strokes missing their first contact point

Replaces `UIPanGestureRecognizer` with direct `touchesBegan/Moved/Ended` handling for ink drawing. The pan gesture had a minimum-distance threshold that silently dropped the start of every stroke — most noticeable with third-party styluses (e.g. Metapen) where initial contact is slow and deliberate.

Also disables PDFKit's built-in gesture recognizers while in ink mode, preventing text selection from firing during what was previously the gesture recognition dead zone.
