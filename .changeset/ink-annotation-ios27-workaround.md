---
"@tobyt/expo-pdf-markup": patch
---

Work around an iOS 27 beta PDFKit regression where `PDFAnnotation.add(_:)`/`.paths` silently drops ink annotation stroke geometry. Ink annotations now store and render their own stroke data instead of relying on PDFKit's built-in ink storage, so drawing, persisting, erasing and moving ink markup continues to behave correctly on iOS 27.
