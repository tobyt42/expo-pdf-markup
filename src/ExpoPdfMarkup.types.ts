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
  createdAt?: number;
};

export type Annotation = InkAnnotation | HighlightAnnotation | UnderlineAnnotation | TextAnnotation;

export type AnnotationsData = {
  version: 1;
  annotations: Annotation[];
};

export type AnnotationMode = 'none' | 'ink' | 'highlight' | 'underline' | 'text' | 'eraser';

export type ExpoPdfMarkupViewProps = {
  /** Local file path or remote URL of the PDF to display. */
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
  /** Fired when the visible page changes. */
  onPageChanged?: (event: { nativeEvent: { page: number; pageCount: number } }) => void;
  /** Fired once the document has finished loading. */
  onLoadComplete?: (event: { nativeEvent: { pageCount: number } }) => void;
  /** Fired when the document fails to load. */
  onError?: (event: { nativeEvent: { message: string } }) => void;
  /** Fired after annotations are created or edited. `annotations` is a serialised {@link AnnotationsData} JSON string. */
  onAnnotationsChanged?: (event: { nativeEvent: { annotations: string } }) => void;
  style?: StyleProp<ViewStyle>;
};
