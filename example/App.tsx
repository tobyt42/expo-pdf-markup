import { ExpoPdfMarkupView } from '@tobyt/expo-pdf-markup';
import type { AnnotationMode } from '@tobyt/expo-pdf-markup';
import { Asset } from 'expo-asset';
import { useFonts } from 'expo-font';
import { useEffect, useRef, useState } from 'react';
import { Modal, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';

const MODES: { label: string; mode: AnnotationMode }[] = [
  { label: 'View', mode: 'none' },
  { label: 'Ink', mode: 'ink' },
  { label: 'Highlight', mode: 'highlight' },
  { label: 'Underline', mode: 'underline' },
  { label: 'Text', mode: 'text' },
  { label: 'Eraser', mode: 'eraser' },
];

const COLORS = [
  { label: 'Red', value: '#FF0000' },
  { label: 'Blue', value: '#0000FF' },
  { label: 'Yellow', value: '#FFFF00' },
  { label: 'Green', value: '#00CC00' },
];

const EMPTY_ANNOTATIONS = JSON.stringify({ version: 1, annotations: [] });

export default function App() {
  const [fontsLoaded] = useFonts({
    'Montserrat-Regular': require('./assets/fonts/Montserrat-Regular.ttf'),
    'Montserrat-Medium': require('./assets/fonts/Montserrat-Medium.ttf'),
  });
  const [pdfPath, setPdfPath] = useState<string | null>(null);
  const [annotationMode, setAnnotationMode] = useState<AnnotationMode>('none');
  const [annotationColor, setAnnotationColor] = useState('#FF0000');
  const [annotations, setAnnotations] = useState(EMPTY_ANNOTATIONS);

  // Custom text dialog state
  const [textDialogVisible, setTextDialogVisible] = useState(false);
  const [textInput, setTextInput] = useState('');
  const resolveRef = useRef<((text: string | null) => void) | null>(null);

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

  const handleTextInputRequested = (): Promise<string | null> => {
    setTextInput('');
    setTextDialogVisible(true);
    return new Promise((resolve) => {
      resolveRef.current = resolve;
    });
  };

  const submitText = () => {
    setTextDialogVisible(false);
    resolveRef.current?.(textInput.trim() || null);
    resolveRef.current = null;
  };

  const cancelText = () => {
    setTextDialogVisible(false);
    resolveRef.current?.(null);
    resolveRef.current = null;
  };

  return (
    <SafeAreaProvider>
      <SafeAreaView style={styles.container}>
        {!pdfPath || !fontsLoaded ? (
          <Text style={styles.loading}>Loading PDF...</Text>
        ) : (
          <ExpoPdfMarkupView
            source={pdfPath}
            style={styles.pdf}
            annotations={annotations}
            annotationMode={annotationMode}
            annotationColor={annotationColor}
            annotationLineWidth={3}
            annotationFontFamily="Montserrat-Regular"
            onTextInputRequested={handleTextInputRequested}
            onLoadComplete={({ nativeEvent: { pageCount } }) =>
              console.log(`PDF loaded: ${pageCount} pages`)
            }
            onPageChanged={({ nativeEvent: { page, pageCount } }) =>
              console.log(`Page ${page + 1} of ${pageCount}`)
            }
            onError={({ nativeEvent: { message } }) => console.error(`PDF error: ${message}`)}
            onAnnotationsChanged={({ nativeEvent }) => setAnnotations(nativeEvent.annotations)}
          />
        )}

        <View style={styles.toolbar}>
          <ScrollView horizontal showsHorizontalScrollIndicator={false} style={styles.toolbarRow}>
            {MODES.map(({ label, mode }) => (
              <Pressable
                key={mode}
                style={[styles.button, annotationMode === mode && styles.buttonActive]}
                onPress={() => setAnnotationMode(mode)}
              >
                <Text
                  style={[styles.buttonText, annotationMode === mode && styles.buttonTextActive]}
                >
                  {label}
                </Text>
              </Pressable>
            ))}
          </ScrollView>

          <View style={styles.toolbarRow}>
            {COLORS.map(({ label, value }) => (
              <Pressable
                key={value}
                style={[
                  styles.colorButton,
                  { backgroundColor: value },
                  annotationColor === value && styles.colorButtonActive,
                ]}
                onPress={() => setAnnotationColor(value)}
              >
                <Text style={styles.colorLabel}>{label}</Text>
              </Pressable>
            ))}

            <Pressable
              style={[styles.button, styles.clearButton]}
              onPress={() => setAnnotations(EMPTY_ANNOTATIONS)}
            >
              <Text style={styles.buttonText}>Clear All</Text>
            </Pressable>
          </View>
        </View>

        <Modal visible={textDialogVisible} transparent animationType="fade">
          <View style={styles.modalOverlay}>
            <View style={styles.modalCard}>
              <Text style={styles.modalTitle}>Add Text</Text>
              <TextInput
                style={styles.modalInput}
                placeholder="Enter annotation text…"
                placeholderTextColor="#888"
                value={textInput}
                onChangeText={setTextInput}
                autoFocus
                onSubmitEditing={submitText}
                returnKeyType="done"
              />
              <View style={styles.modalActions}>
                <Pressable style={styles.modalCancel} onPress={cancelText}>
                  <Text style={styles.modalCancelText}>Cancel</Text>
                </Pressable>
                <Pressable style={styles.modalConfirm} onPress={submitText}>
                  <Text style={styles.modalConfirmText}>Add</Text>
                </Pressable>
              </View>
            </View>
          </View>
        </Modal>
      </SafeAreaView>
    </SafeAreaProvider>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#333',
  },
  loading: {
    color: '#fff',
    textAlign: 'center',
    marginTop: 100,
  },
  pdf: {
    flex: 1,
  },
  toolbar: {
    backgroundColor: '#222',
    paddingVertical: 8,
    paddingHorizontal: 8,
    gap: 6,
  },
  toolbarRow: {
    flexDirection: 'row',
  },
  button: {
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 6,
    backgroundColor: '#444',
    marginRight: 6,
  },
  buttonActive: {
    backgroundColor: '#0A84FF',
  },
  buttonText: {
    color: '#ccc',
    fontSize: 13,
    fontWeight: '600',
  },
  buttonTextActive: {
    color: '#fff',
  },
  colorButton: {
    width: 36,
    height: 36,
    borderRadius: 18,
    marginRight: 8,
    justifyContent: 'center',
    alignItems: 'center',
    borderWidth: 2,
    borderColor: 'transparent',
  },
  colorButtonActive: {
    borderColor: '#fff',
  },
  colorLabel: {
    fontSize: 8,
    color: '#fff',
    fontWeight: '700',
    textShadowColor: '#000',
    textShadowOffset: { width: 0, height: 1 },
    textShadowRadius: 2,
  },
  clearButton: {
    backgroundColor: '#8B0000',
    marginLeft: 'auto',
  },
  // Modal
  modalOverlay: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.55)',
    justifyContent: 'center',
    alignItems: 'center',
    padding: 32,
  },
  modalCard: {
    backgroundColor: '#1e1e1e',
    borderRadius: 14,
    padding: 20,
    width: '100%',
    maxWidth: 360,
    gap: 16,
  },
  modalTitle: {
    color: '#fff',
    fontSize: 17,
    fontWeight: '700',
  },
  modalInput: {
    backgroundColor: '#2c2c2e',
    color: '#fff',
    borderRadius: 8,
    paddingHorizontal: 12,
    paddingVertical: 10,
    fontSize: 15,
  },
  modalActions: {
    flexDirection: 'row',
    justifyContent: 'flex-end',
    gap: 10,
  },
  modalCancel: {
    paddingHorizontal: 16,
    paddingVertical: 9,
    borderRadius: 8,
    backgroundColor: '#3a3a3c',
  },
  modalCancelText: {
    color: '#ccc',
    fontWeight: '600',
    fontSize: 14,
  },
  modalConfirm: {
    paddingHorizontal: 16,
    paddingVertical: 9,
    borderRadius: 8,
    backgroundColor: '#0A84FF',
  },
  modalConfirmText: {
    color: '#fff',
    fontWeight: '700',
    fontSize: 14,
  },
});
