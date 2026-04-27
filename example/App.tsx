import type { AnnotationMode } from '@tobyt/expo-pdf-markup';
import { Asset } from 'expo-asset';
import { useFonts } from 'expo-font';
import { useEffect, useState } from 'react';
import { View } from 'react-native';
import { SafeAreaProvider } from 'react-native-safe-area-context';

import AnnotationsScreen from './screens/AnnotationsScreen';
import PdfScreen from './screens/PdfScreen';

const EMPTY_ANNOTATIONS = JSON.stringify({ version: 1, annotations: [] });

type ScreenName = 'pdf' | 'annotations';

export default function App() {
  const [fontsLoaded] = useFonts({
    'Montserrat-Regular': require('./assets/fonts/Montserrat-Regular.ttf'),
    'Montserrat-Medium': require('./assets/fonts/Montserrat-Medium.ttf'),
  });
  const [pdfPath, setPdfPath] = useState<string | null>(null);
  const [annotationMode, setAnnotationMode] = useState<AnnotationMode>('none');
  const [annotationColor, setAnnotationColor] = useState('#FF0000');
  const [annotations, setAnnotations] = useState(EMPTY_ANNOTATIONS);

  const [stack, setStack] = useState<ScreenName[]>(['pdf']);
  const push = (name: ScreenName) => setStack((s) => [...s, name]);
  const pop = () => setStack((s) => s.slice(0, -1));
  const currentScreen = stack[stack.length - 1];

  useEffect(() => {
    async function preparePdf() {
      const asset = Asset.fromModule(require('./assets/test.pdf'));
      await asset.downloadAsync();
      if (asset.localUri) {
        setPdfPath(asset.localUri.replace('file://', ''));
      }
    }
    preparePdf();
  }, []);

  return (
    <SafeAreaProvider>
      <View style={{ flex: 1, display: currentScreen === 'pdf' ? 'flex' : 'none' }}>
        <PdfScreen
          pdfPath={pdfPath}
          fontsLoaded={fontsLoaded}
          annotations={annotations}
          annotationMode={annotationMode}
          annotationColor={annotationColor}
          onAnnotationsChanged={setAnnotations}
          onAnnotationModeChange={setAnnotationMode}
          onAnnotationColorChange={setAnnotationColor}
          onClearAnnotations={() => setAnnotations(EMPTY_ANNOTATIONS)}
          onNavigateToAnnotations={() => push('annotations')}
        />
      </View>
      <View style={{ flex: 1, display: currentScreen === 'annotations' ? 'flex' : 'none' }}>
        <AnnotationsScreen
          annotations={annotations}
          onClearAnnotations={() => setAnnotations(EMPTY_ANNOTATIONS)}
          onGoBack={pop}
        />
      </View>
    </SafeAreaProvider>
  );
}
