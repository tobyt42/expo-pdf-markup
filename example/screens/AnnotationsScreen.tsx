import type { Annotation, AnnotationsData } from '@tobyt/expo-pdf-markup';
import { useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

type Props = {
  annotations: string;
  onClearAnnotations: () => void;
  onGoBack: () => void;
};

function annotationSummary(annotation: Annotation): string {
  switch (annotation.type) {
    case 'ink':
      return `${annotation.paths.length} path${annotation.paths.length !== 1 ? 's' : ''}`;
    case 'highlight':
    case 'underline':
      return `(${Math.round(annotation.bounds.x)}, ${Math.round(annotation.bounds.y)})`;
    case 'text':
    case 'freeText':
      return annotation.contents ? `"${annotation.contents}"` : '(empty)';
  }
}

const TYPE_COLORS: Record<string, string> = {
  ink: '#0A84FF',
  highlight: '#FFD60A',
  underline: '#30D158',
  text: '#FF9F0A',
  freeText: '#FF9F0A',
};

export default function AnnotationsScreen({ annotations, onClearAnnotations, onGoBack }: Props) {
  const [showRaw, setShowRaw] = useState(false);

  let parsed: AnnotationsData | null = null;
  try {
    parsed = JSON.parse(annotations) as AnnotationsData;
  } catch {
    // malformed JSON — handled below
  }

  const items = parsed?.annotations ?? [];

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.header}>
        <Pressable style={styles.backButton} onPress={onGoBack}>
          <Text style={styles.backText}>← Back</Text>
        </Pressable>
        <Text style={styles.title}>Annotations</Text>
        <Pressable style={styles.clearButton} onPress={onClearAnnotations}>
          <Text style={styles.clearText}>Clear All</Text>
        </Pressable>
      </View>

      <ScrollView style={styles.list} contentContainerStyle={styles.listContent}>
        {items.length === 0 ? (
          <Text style={styles.empty}>No annotations yet. Draw on the PDF to add some.</Text>
        ) : (
          items.map((annotation, index) => (
            <View key={annotation.id ?? index} style={styles.card}>
              <View style={styles.cardHeader}>
                <View
                  style={[
                    styles.typeBadge,
                    { backgroundColor: TYPE_COLORS[annotation.type] ?? '#888' },
                  ]}
                >
                  <Text style={styles.typeText}>{annotation.type}</Text>
                </View>
                <Text style={styles.pagePill}>Page {annotation.page + 1}</Text>
                <View style={[styles.colorSwatch, { backgroundColor: annotation.color }]} />
              </View>
              <Text style={styles.cardDetail}>{annotationSummary(annotation)}</Text>
            </View>
          ))
        )}

        <Pressable style={styles.rawToggle} onPress={() => setShowRaw((v) => !v)}>
          <Text style={styles.rawToggleText}>{showRaw ? 'Hide raw JSON' : 'Show raw JSON'}</Text>
        </Pressable>

        {showRaw && (
          <View style={styles.rawCard}>
            <Text style={styles.rawText}>{JSON.stringify(parsed, null, 2)}</Text>
          </View>
        )}
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#1a1a1a',
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 12,
    backgroundColor: '#222',
    borderBottomWidth: 1,
    borderBottomColor: '#333',
  },
  backButton: {
    paddingVertical: 4,
    paddingRight: 12,
  },
  backText: {
    color: '#0A84FF',
    fontSize: 16,
    fontWeight: '600',
  },
  title: {
    flex: 1,
    color: '#fff',
    fontSize: 17,
    fontWeight: '700',
    textAlign: 'center',
  },
  clearButton: {
    paddingVertical: 4,
    paddingLeft: 12,
  },
  clearText: {
    color: '#FF453A',
    fontSize: 14,
    fontWeight: '600',
  },
  list: {
    flex: 1,
  },
  listContent: {
    padding: 16,
    gap: 10,
  },
  empty: {
    color: '#888',
    fontSize: 14,
    textAlign: 'center',
    marginTop: 40,
    lineHeight: 22,
  },
  card: {
    backgroundColor: '#2c2c2e',
    borderRadius: 10,
    padding: 12,
    gap: 6,
  },
  cardHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  typeBadge: {
    paddingHorizontal: 8,
    paddingVertical: 3,
    borderRadius: 5,
  },
  typeText: {
    color: '#fff',
    fontSize: 11,
    fontWeight: '700',
    textTransform: 'uppercase',
    letterSpacing: 0.5,
  },
  pagePill: {
    color: '#aaa',
    fontSize: 12,
    fontWeight: '600',
  },
  colorSwatch: {
    width: 16,
    height: 16,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: '#555',
    marginLeft: 'auto',
  },
  cardDetail: {
    color: '#ccc',
    fontSize: 13,
  },
  rawToggle: {
    marginTop: 16,
    alignSelf: 'center',
    paddingVertical: 8,
    paddingHorizontal: 16,
    borderRadius: 8,
    backgroundColor: '#2c2c2e',
  },
  rawToggleText: {
    color: '#0A84FF',
    fontSize: 13,
    fontWeight: '600',
  },
  rawCard: {
    marginTop: 8,
    backgroundColor: '#111',
    borderRadius: 10,
    padding: 12,
  },
  rawText: {
    color: '#0F0',
    fontSize: 11,
    fontFamily: 'monospace',
    lineHeight: 16,
  },
});
