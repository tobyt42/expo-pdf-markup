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
  type: 'text';
  page: number;
  color: string;
  bounds: AnnotationBounds;
  contents?: string;
  createdAt?: number;
};

export type Annotation = InkAnnotation | HighlightAnnotation | UnderlineAnnotation | TextAnnotation;

export type AnnotationsData = {
  version: 1;
  annotations: Annotation[];
};

export type AnnotationMode = 'none' | 'ink' | 'highlight' | 'underline' | 'text' | 'eraser';

export type ExpoPdfMarkupViewProps = {
  source: string;
  page?: number;
  backgroundColor?: string;
  annotations?: string;
  annotationMode?: AnnotationMode;
  annotationColor?: string;
  annotationLineWidth?: number;
  onPageChanged?: (event: { nativeEvent: { page: number; pageCount: number } }) => void;
  onLoadComplete?: (event: { nativeEvent: { pageCount: number } }) => void;
  onError?: (event: { nativeEvent: { message: string } }) => void;
  onAnnotationsChanged?: (event: { nativeEvent: { annotations: string } }) => void;
  style?: StyleProp<ViewStyle>;
};
