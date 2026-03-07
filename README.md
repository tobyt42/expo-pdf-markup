# @tobyt/expo-pdf-markup

An Expo module for displaying and annotating PDFs, with support for iOS, Android, and Web.

> **Status:** Early development. Not yet published to npm.

## Roadmap

### Phase 1 — iOS: PDF rendering

- [ ] Render a PDF from a local file path (PDFKit)
- [ ] Fit-to-width, pinch zoom, double-tap zoom
- [ ] `onPageChanged(page, total)` callback
- [ ] Controlled `page` prop (for page restoration on orientation change)

### Phase 2 — iOS: Annotations

- [ ] `annotations` prop — load annotation JSON on open
- [ ] `onAnnotationsChanged` callback — emit updated JSON after edits
- [ ] Annotation type: ink / freehand drawing + eraser
- [ ] Annotation type: highlight and underline
- [ ] Annotation type: sticky notes / text comments
- [ ] Annotation JSON serialisation and deserialisation (Swift)

### Phase 3 — Android: PDF rendering

- [ ] Render a PDF from a local file path (Android PdfRenderer or PdfiumAndroid)
- [ ] Fit-to-width, pinch zoom, double-tap zoom
- [ ] Same callback and prop API as iOS

### Phase 4 — Android: Annotations

- [ ] Annotation support (ink, highlight, sticky notes)
- [ ] Annotation JSON serialisation and deserialisation (Kotlin)
- [ ] Cross-platform annotation portability (iOS ↔ Android)

### Phase 5 — Web: PDF rendering

- [ ] PDF rendering (pdf.js / react-pdf)

### Phase 6 — Web: Annotations

- [ ] Annotation creation and editing
- [ ] Same JSON serialisation format as mobile

## Installation

```sh
npm install @tobyt/expo-pdf-markup
```

### iOS

```sh
npx pod-install
```

## Usage

```tsx
import { ExpoPdfMarkupView } from '@tobyt/expo-pdf-markup';

export default function App() {
  return <ExpoPdfMarkupView source={{ uri: 'https://example.com/document.pdf' }} />;
}
```

## Development

This module uses the [Expo Modules API](https://docs.expo.dev/modules/overview/). The `example` directory contains a test app.

```sh
# Build the module
npm run build

# Run the example app
cd example
npx expo start
```

## License

MIT
