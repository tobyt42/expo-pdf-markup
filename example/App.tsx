import { ExpoPdfMarkupView } from '@tobyt/expo-pdf-markup';
import { Asset } from 'expo-asset';
import { useEffect, useState } from 'react';
import { StyleSheet, Text } from 'react-native';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';

export default function App() {
  const [pdfPath, setPdfPath] = useState<string | null>(null);

  useEffect(() => {
    async function preparePdf() {
      const asset = Asset.fromModule(require('./assets/test.pdf'));
      await asset.downloadAsync();
      const resolved = asset;
      if (resolved.localUri) {
        setPdfPath(resolved.localUri.replace('file://', ''));
      }
    }
    preparePdf();
  }, []);

  return (
    <SafeAreaProvider>
      <SafeAreaView style={styles.container}>
        {!pdfPath ? (
          <Text>Loading PDF...</Text>
        ) : (
          <ExpoPdfMarkupView
            source={pdfPath}
            style={styles.pdf}
            onLoadComplete={({ nativeEvent: { pageCount } }) =>
              console.log(`PDF loaded: ${pageCount} pages`)
            }
            onPageChanged={({ nativeEvent: { page, pageCount } }) =>
              console.log(`Page ${page + 1} of ${pageCount}`)
            }
            onError={({ nativeEvent: { message } }) => console.error(`PDF error: ${message}`)}
          />
        )}
      </SafeAreaView>
    </SafeAreaProvider>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#333',
  },
  pdf: {
    flex: 1,
  },
});
