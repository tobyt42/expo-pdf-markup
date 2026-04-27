import { ExpoPdfMarkupView } from '@tobyt/expo-pdf-markup';
import type { AnnotationMode, TextInputRequest } from '@tobyt/expo-pdf-markup';
import { useRef, useState } from 'react';
import { Modal, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

const MODES: { label: string; mode: AnnotationMode }[] = [
  { label: 'View', mode: 'none' },
  { label: 'Ink', mode: 'ink' },
  { label: 'Highlight', mode: 'highlight' },
  { label: 'Underline', mode: 'underline' },
  { label: 'Text', mode: 'text' },
  { label: 'Move', mode: 'move' },
  { label: 'Eraser', mode: 'eraser' },
];

const COLORS = [
  { label: 'Red', value: '#FF0000' },
  { label: 'Blue', value: '#0000FF' },
  { label: 'Yellow', value: '#FFFF00' },
  { label: 'Green', value: '#00CC00' },
];

type Props = {
  pdfPath: string | null;
  fontsLoaded: boolean;
  annotations: string;
  annotationMode: AnnotationMode;
  annotationColor: string;
  onAnnotationsChanged: (annotations: string) => void;
  onAnnotationModeChange: (mode: AnnotationMode) => void;
  onAnnotationColorChange: (color: string) => void;
  onClearAnnotations: () => void;
  onNavigateToAnnotations: () => void;
};

export default function PdfScreen({
  pdfPath,
  fontsLoaded,
  annotations,
  annotationMode,
  annotationColor,
  onAnnotationsChanged,
  onAnnotationModeChange,
  onAnnotationColorChange,
  onClearAnnotations,
  onNavigateToAnnotations,
}: Props) {
  const [textDialogVisible, setTextDialogVisible] = useState(false);
  const [textRequest, setTextRequest] = useState<TextInputRequest | null>(null);
  const [textInput, setTextInput] = useState('');
  const resolveRef = useRef<((text: string | null) => void) | null>(null);

  const handleTextInputRequested = (request: TextInputRequest): Promise<string | null> => {
    setTextRequest(request);
    setTextInput(request.currentText ?? '');
    setTextDialogVisible(true);
    return new Promise((resolve) => {
      resolveRef.current = resolve;
    });
  };

  const submitText = () => {
    setTextDialogVisible(false);
    setTextRequest(null);
    resolveRef.current?.(textInput.trim() || null);
    resolveRef.current = null;
  };

  const cancelText = () => {
    setTextDialogVisible(false);
    setTextRequest(null);
    resolveRef.current?.(null);
    resolveRef.current = null;
  };

  return (
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
          onAnnotationsChanged={({ nativeEvent }) => onAnnotationsChanged(nativeEvent.annotations)}
        />
      )}

      <View style={styles.toolbar}>
        <ScrollView horizontal showsHorizontalScrollIndicator={false} style={styles.toolbarRow}>
          {MODES.map(({ label, mode }) => (
            <Pressable
              key={mode}
              style={[styles.button, annotationMode === mode && styles.buttonActive]}
              onPress={() => onAnnotationModeChange(mode)}
            >
              <Text style={[styles.buttonText, annotationMode === mode && styles.buttonTextActive]}>
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
              onPress={() => onAnnotationColorChange(value)}
            >
              <Text style={styles.colorLabel}>{label}</Text>
            </Pressable>
          ))}

          <Pressable
            style={[styles.button, styles.clearButton]}
            onPress={onClearAnnotations}
          >
            <Text style={styles.buttonText}>Clear All</Text>
          </Pressable>

          <Pressable style={[styles.button, styles.annotationsButton]} onPress={onNavigateToAnnotations}>
            <Text style={styles.buttonText}>Annotations</Text>
          </Pressable>
        </View>
      </View>

      <Modal visible={textDialogVisible} transparent animationType="fade">
        <View style={styles.modalOverlay}>
          <View style={styles.modalCard}>
            <Text style={styles.modalTitle}>
              {textRequest?.mode === 'edit' ? 'Edit Text' : 'Add Text'}
            </Text>
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
                <Text style={styles.modalConfirmText}>
                  {textRequest?.mode === 'edit' ? 'Update' : 'Add'}
                </Text>
              </Pressable>
            </View>
          </View>
        </View>
      </Modal>
    </SafeAreaView>
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
  annotationsButton: {
    backgroundColor: '#1a5a1a',
    marginLeft: 6,
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
