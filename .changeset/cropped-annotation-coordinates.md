---
'@tobyt/expo-pdf-markup': patch
---

Correct iOS annotation placement on cropped PDFs, including ink commitment, stamps, editing outlines and move/erase targets. Align loading and serialization with the shared visible-page coordinate contract, including rotated pages, without automatically migrating ambiguous historical v1 data. Keep live text creation and editing stable across reopen, and render stamps and underlines consistently in live views and scaled thumbnails at every page rotation. Consumers must rebuild their native iOS application; a JavaScript-only update does not replace the Swift implementation.
