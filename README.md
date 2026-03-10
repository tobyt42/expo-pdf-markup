# @tobyt/expo-pdf-markup

[![npm version](https://img.shields.io/npm/v/@tobyt/expo-pdf-markup.svg)](https://www.npmjs.com/package/@tobyt/expo-pdf-markup)
[![npm downloads](https://img.shields.io/npm/dw/@tobyt/expo-pdf-markup.svg)](https://www.npmjs.com/package/@tobyt/expo-pdf-markup)
[![license](https://img.shields.io/npm/l/@tobyt/expo-pdf-markup.svg)](https://github.com/tobyt42/expo-pdf-markup/blob/main/LICENSE)
[![TypeScript](https://img.shields.io/badge/TypeScript-strict-blue.svg)](https://www.typescriptlang.org/)

An Expo module for displaying and annotating PDFs, with support for iOS, Android, and Web.

> **Status:** Early development — actively tested in the [Choir](https://www.thechoirapp.com) app.

## Platform support

| Platform | PDF rendering | Annotations |
| -------- | ------------- | ----------- |
| iOS      | ✅            | ✅          |
| Android  | ✅            | ✅          |
| Web      | ✅            | ✅          |

## Installation

```sh
npm install @tobyt/expo-pdf-markup
```

### iOS

```sh
npx pod-install
```

### Web

Web rendering uses [pdfjs-dist](https://github.com/mozilla/pdfjs-dist). Install it as a dependency:

```sh
npm install pdfjs-dist
```

Then add the Metro config plugin to your `metro.config.js`:

```js
const { getDefaultConfig } = require('expo/metro-config');
const { withPdfMarkup } = require('@tobyt/expo-pdf-markup/metro');

const config = getDefaultConfig(__dirname);
module.exports = withPdfMarkup(config);
```

`withPdfMarkup` does two things automatically:

1. **Patches `import.meta`** in pdfjs-dist so Metro can bundle it (pdfjs-dist v4 uses ESM syntax in a Node.js-only code path that is otherwise unreachable in a browser).
2. **Copies the pdfjs worker** to `public/pdf.worker.min.mjs` in your project root so it is served alongside your app (same-origin, no CORS issues). The default worker URL is `./pdf.worker.min.mjs` (relative to the page), so it works whether your app is hosted at the root or a sub-path.

The `public/pdf.worker.min.mjs` file is regenerated on each Metro start if missing, so you can add it to `.gitignore`:

```
public/pdf.worker.min.mjs
```

#### Using a different worker URL

If you are not using Metro (e.g. Webpack or a custom CDN), set the worker URL before mounting the view:

```ts
import { setPdfJsWorkerSrc } from '@tobyt/expo-pdf-markup';

setPdfJsWorkerSrc('https://your-cdn.example.com/pdf.worker.min.mjs');
```

#### Asset loading on web

`expo-asset` returns a full URL on web (`https://…` or `http://…`), not a local path. Pass it directly to `source` — pdfjs accepts URLs:

```ts
// asset.localUri on web is already a URL; the .replace() is a no-op
setPdfPath(asset.localUri.replace('file://', ''));
```

## Usage

Full API reference is available at **[tobyt42.github.io/expo-pdf-markup](https://tobyt42.github.io/expo-pdf-markup/api/types/ExpoPdfMarkupViewProps.html)**.

```tsx
import { ExpoPdfMarkupView } from '@tobyt/expo-pdf-markup';
import type { AnnotationMode } from '@tobyt/expo-pdf-markup';
import { Asset } from 'expo-asset';
import { useEffect, useState } from 'react';
import { StyleSheet } from 'react-native';

export default function App() {
  const [pdfPath, setPdfPath] = useState<string | null>(null);
  const [annotations, setAnnotations] = useState(JSON.stringify({ version: 1, annotations: [] }));

  useEffect(() => {
    async function preparePdf() {
      const asset = Asset.fromModule(require('./assets/document.pdf'));
      await asset.downloadAsync();
      if (asset.localUri) setPdfPath(asset.localUri.replace('file://', ''));
    }
    preparePdf();
  }, []);

  if (!pdfPath) return null;

  return (
    <ExpoPdfMarkupView
      source={pdfPath}
      style={StyleSheet.absoluteFill}
      annotationMode="ink"
      annotationColor="#FF0000"
      annotationLineWidth={3}
      annotations={annotations}
      onLoadComplete={({ nativeEvent: { pageCount } }) => console.log(`Loaded ${pageCount} pages`)}
      onPageChanged={({ nativeEvent: { page, pageCount, pageWidth, pageHeight } }) =>
        console.log(`Page ${page + 1} of ${pageCount} (${pageWidth}×${pageHeight}pt)`)
      }
      onAnnotationsChanged={({ nativeEvent }) => setAnnotations(nativeEvent.annotations)}
      onError={({ nativeEvent: { message } }) => console.error(message)}
    />
  );
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

## Core Team

<table>
  <tr>
    <td align="center"><a href="https://github.com/tobyt42"><img src="https://avatars.githubusercontent.com/u/1678364?v=4" width="100px;" alt=""/><br /><sub><b>Toby Terhoeven</b></sub></a><br /></td>
  </tr>
</table>

## License

MIT
