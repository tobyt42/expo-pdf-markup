import type { StyleProp, ViewStyle } from 'react-native';

export type ExpoPdfMarkupViewProps = {
  source: string;
  page?: number;
  onPageChanged?: (event: { nativeEvent: { page: number; pageCount: number } }) => void;
  onLoadComplete?: (event: { nativeEvent: { pageCount: number } }) => void;
  onError?: (event: { nativeEvent: { message: string } }) => void;
  style?: StyleProp<ViewStyle>;
};
