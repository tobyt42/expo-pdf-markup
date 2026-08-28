---
"@tobyt/expo-pdf-markup": patch
---

Revert the iOS 27 beta workaround for the PDFKit ink annotation regression. Ink annotations use PDFKit's built-in ink storage again now that `PDFAnnotation.add(_:)`/`.paths` behaves correctly, restoring the standard rendering and serialisation behaviour.
