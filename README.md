# @tobyt/expo-pdf-markup

[![npm version](https://img.shields.io/npm/v/@tobyt/expo-pdf-markup.svg)](https://www.npmjs.com/package/@tobyt/expo-pdf-markup)
[![npm downloads](https://img.shields.io/npm/dw/@tobyt/expo-pdf-markup.svg)](https://www.npmjs.com/package/@tobyt/expo-pdf-markup)
[![license](https://img.shields.io/npm/l/@tobyt/expo-pdf-markup.svg)](https://github.com/tobyt42/expo-pdf-markup/blob/main/LICENSE)
[![TypeScript](https://img.shields.io/badge/TypeScript-strict-blue.svg)](https://www.typescriptlang.org/)

An Expo module for displaying and annotating PDFs, with support for iOS, Android, and Web.

> **Status:** Early development — actively being tested. Web support is planned and will be added soon.

## Platform support

| Platform | PDF rendering | Annotations |
| -------- | ------------- | ----------- |
| iOS      | ✅            | ✅          |
| Android  | ✅            | ✅          |
| Web      | 🔜            | 🔜          |

## Installation

```sh
npm install @tobyt/expo-pdf-markup
```

### iOS

```sh
npx pod-install
```

## Usage

Full API reference is available at **[tobyt42.github.io/expo-pdf-markup](https://tobyt42.github.io/expo-pdf-markup/types/ExpoPdfMarkupViewProps.html)**.

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
      onPageChanged={({ nativeEvent: { page, pageCount } }) =>
        console.log(`Page ${page + 1} of ${pageCount}`)
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
