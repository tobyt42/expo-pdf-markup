import type { AnnotationMode } from '@tobyt/expo-pdf-markup';
import { Asset } from 'expo-asset';
import { useFonts } from 'expo-font';
import { useEffect, useState } from 'react';
import { View } from 'react-native';
import { SafeAreaProvider } from 'react-native-safe-area-context';

import AnnotationsScreen from './screens/AnnotationsScreen';
import PdfScreen, { type SampleDocument } from './screens/PdfScreen';

const EMPTY_ANNOTATIONS = JSON.stringify({ version: 1, annotations: [] });

// book-sample.pdf and single-page.pdf come from scripts/generate_sample_pdfs.py.
const DOCUMENTS: (SampleDocument & { module: number })[] = [
  { id: 'test', label: 'Test (2 pages)', module: require('./assets/test.pdf') },
  { id: 'book', label: 'Book sample (6 pages)', module: require('./assets/book-sample.pdf') },
  { id: 'single', label: 'Single page', module: require('./assets/single-page.pdf') },
];

type ScreenName = 'pdf' | 'annotations';

export default function App() {
  const [fontsLoaded] = useFonts({
    'Montserrat-Regular': require('./assets/fonts/Montserrat-Regular.ttf'),
    'Montserrat-Medium': require('./assets/fonts/Montserrat-Medium.ttf'),
  });
  const [documentId, setDocumentId] = useState(DOCUMENTS[0]!.id);
  const [pdfPath, setPdfPath] = useState<string | null>(null);
  const [annotationMode, setAnnotationMode] = useState<AnnotationMode>('none');
  const [annotationColor, setAnnotationColor] = useState('#FF0000');
  const [annotations, setAnnotations] = useState(EMPTY_ANNOTATIONS);

  const [stack, setStack] = useState<ScreenName[]>(['pdf']);
  const push = (name: ScreenName) => setStack((s) => [...s, name]);
  const pop = () => setStack((s) => s.slice(0, -1));
  const currentScreen = stack[stack.length - 1];

  useEffect(() => {
    let cancelled = false;
    async function preparePdf() {
      const document = DOCUMENTS.find((d) => d.id === documentId) ?? DOCUMENTS[0]!;
      const asset = Asset.fromModule(document.module);
      await asset.downloadAsync();
      if (!cancelled && asset.localUri) {
        setPdfPath(asset.localUri.replace('file://', ''));
      }
    }
    preparePdf();
    return () => {
      cancelled = true;
    };
  }, [documentId]);

  const changeDocument = (id: string) => {
    if (id === documentId) return;
    // Annotations belong to a document, so the new one starts with none.
    setAnnotations(EMPTY_ANNOTATIONS);
    setPdfPath(null);
    setDocumentId(id);
  };

  return (
    <SafeAreaProvider>
      <View style={{ flex: 1, display: currentScreen === 'pdf' ? 'flex' : 'none' }}>
        <PdfScreen
          pdfPath={pdfPath}
          fontsLoaded={fontsLoaded}
          documents={DOCUMENTS}
          documentId={documentId}
          onDocumentChange={changeDocument}
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
