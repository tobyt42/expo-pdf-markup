# @tobyt/expo-pdf-markup

An Expo module for displaying and annotating PDFs, with support for iOS, Android, and Web.

> **Status:** Early development — actively being tested. Web support is planned and will be added soon.

## Platform support

| Platform | PDF rendering | Annotations |
| -------- | ------------- | ----------- |
| iOS      | ✅             | ✅           |
| Android  | ✅             | ✅           |
| Web      | 🔜             | 🔜           |

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
