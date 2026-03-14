import type { StyleProp, ViewStyle } from 'react-native';

export type AnnotationPoint = { x: number; y: number };

export type AnnotationBounds = { x: number; y: number; width: number; height: number };

export type InkAnnotation = {
  id: string;
  type: 'ink';
  page: number;
  color: string;
  lineWidth: number;
  paths: AnnotationPoint[][];
  createdAt?: number;
};

export type HighlightAnnotation = {
  id: string;
  type: 'highlight';
  page: number;
  color: string;
  alpha?: number;
  bounds: AnnotationBounds;
  createdAt?: number;
};

export type UnderlineAnnotation = {
  id: string;
  type: 'underline';
  page: number;
  color: string;
  bounds: AnnotationBounds;
  createdAt?: number;
};

export type TextAnnotation = {
  id: string;
  type: 'text' | 'freeText';
  page: number;
  color: string;
  bounds: AnnotationBounds;
  contents?: string;
  fontSize?: number;
  /**
   * Font family for the text annotation. Platform-specific:
   * - iOS: PostScript name (`"Georgia"`, `"Courier"`) or `undefined` for system font (San Francisco)
   * - Android: family name (`"serif"`, `"monospace"`) or `undefined` for default sans-serif
   * - Web: CSS font family (`"Georgia, serif"`) or `undefined` for `sans-serif`
   */
  fontFamily?: string;
  createdAt?: number;
};

export type Annotation = InkAnnotation | HighlightAnnotation | UnderlineAnnotation | TextAnnotation;

export type AnnotationsData = {
  version: 1;
  annotations: Annotation[];
};

export type AnnotationMode = 'none' | 'ink' | 'highlight' | 'underline' | 'text' | 'eraser';

export type ExpoPdfMarkupViewProps = {
  /** Absolute local file path of the PDF to display. */
  source: string;
  /** 0-based page number to display. Can be used to restore scroll position on orientation change. */
  page?: number;
  /** Background colour shown behind the PDF pages. */
  backgroundColor?: string;
  /** Serialised {@link AnnotationsData} JSON string to load when the document opens. */
  annotations?: string;
  /** Active annotation tool. Defaults to `'none'` (view-only). */
  annotationMode?: AnnotationMode;
  /** Colour applied to new annotations, as a CSS colour string (e.g. `'#FF0000'`). */
  annotationColor?: string;
  /** Stroke width in points applied to new ink annotations. */
  annotationLineWidth?: number;
  /**
   * Default font family for new text annotations. Platform-specific:
   * - iOS: PostScript name (`"Georgia"`, `"Courier"`) or `undefined` for system font (San Francisco)
   * - Android: family name (`"serif"`, `"monospace"`) or `undefined` for default sans-serif
   * - Web: CSS font family (`"Georgia, serif"`) or `undefined` for `sans-serif`
   */
  annotationFontFamily?: string;
  /** Fired when the visible page changes. */
  onPageChanged?: (event: {
    nativeEvent: { page: number; pageCount: number; pageWidth: number; pageHeight: number };
  }) => void;
  /** Fired once the document has finished loading. */
  onLoadComplete?: (event: { nativeEvent: { pageCount: number } }) => void;
  /** Fired when the document fails to load. */
  onError?: (event: { nativeEvent: { message: string } }) => void;
  /** Fired after annotations are created or edited. `annotations` is a serialised {@link AnnotationsData} JSON string. */
  onAnnotationsChanged?: (event: { nativeEvent: { annotations: string } }) => void;
  /**
   * Optional async callback for the text annotation tool. When provided, this is called instead of
   * the native platform dialog (UIAlertController / AlertDialog) when the user taps to place a text
   * annotation. Return the text string to create the annotation, or `null` to cancel.
   */
  onTextInputRequested?: () => Promise<string | null>;
  style?: StyleProp<ViewStyle>;
};
