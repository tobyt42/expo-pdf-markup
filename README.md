# @tobyt/expo-pdf-markup

An Expo module for displaying and annotating PDFs, with support for iOS, Android, and Web.

> **Status:** Early development. Not yet published to npm.

## Roadmap

### Phase 1 — iOS: PDF rendering

- [x] Render a PDF from a local file path (PDFKit)
- [x] Fit-to-width, pinch zoom, double-tap zoom
- [x] `onPageChanged(page, total)` callback
- [x] Controlled `page` prop (for page restoration on orientation change)

### Phase 2 — Android: PDF rendering

- [x] Render a PDF from a local file path (Android PdfRenderer)
- [x] Fit-to-width, pinch zoom, double-tap zoom
- [x] Same callback and prop API as iOS

### Phase 3 — iOS: Annotations

- [x] `annotations` prop — load annotation JSON on open
- [x] `onAnnotationsChanged` callback — emit updated JSON after edits
- [x] Annotation type: ink / freehand drawing + eraser
- [x] Annotation type: highlight and underline
- [x] Annotation type: free text
- [x] Annotation JSON serialisation and deserialisation (Swift)

### Phase 4 — Android: Annotations

- [x] Annotation support (ink, highlight, free text)
- [x] Annotation JSON serialisation and deserialisation (Kotlin)
- [x] Cross-platform annotation portability (iOS ↔ Android)

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
