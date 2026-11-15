---
'@tobyt/expo-pdf-markup': major
---

Fix iOS annotation placement, moving and erasing on cropped or rotated PDFs, including stamps in thumbnails and text after reopening.

iOS annotation coordinates and `onTextInputRequested.point` now use the visible page, with `(0, 0)` at its bottom-left after rotation. Some annotations saved by older iOS versions may move; existing data is not automatically migrated. Back up saved annotations before upgrading.

Rebuild your native iOS app to apply these fixes.
