# expo-pdf-markup

Displaying PDFs and letting people mark them up, with annotations exchanged as JSON shared by the iOS, Android and web implementations.

**Host app**:
The app that embeds this library and stores its annotation sets, such as the Choir App.
_Avoid_: consumer, client app

## Annotations

**Annotation set**:
The full collection of annotations for one document, exchanged as a single JSON string.
_Avoid_: markup set, annotations blob

**Ink stroke**:
One continuous freehand line within an ink annotation, made of ordered ink points.
_Avoid_: path (when meaning a single stroke), line

**Ink point**:
One position on an ink stroke, in visible-page PDF points with y increasing upwards.
_Avoid_: vertex, coordinate pair

**Ink point format**:
How an ink point is written in an annotation set: object form or array form. Readers accept either, point by point.
_Avoid_: compact encoding, ink encoding

**Object form**:
The ink point format `{"x": …, "y": …}`, and the default.
_Avoid_: legacy format

**Array form**:
The ink point format `[x, y]`, chosen when the host app opts in.
_Avoid_: compact format, tuple format
