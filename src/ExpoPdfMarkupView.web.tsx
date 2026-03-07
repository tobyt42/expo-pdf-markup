import * as React from 'react';
import { Text, View } from 'react-native';

import { ExpoPdfMarkupViewProps } from './ExpoPdfMarkup.types';

export default function ExpoPdfMarkupView(props: ExpoPdfMarkupViewProps) {
  return (
    <View style={[{ flex: 1, alignItems: 'center', justifyContent: 'center' }, props.style]}>
      <Text>PDF viewing is not yet supported on web.</Text>
    </View>
  );
}
