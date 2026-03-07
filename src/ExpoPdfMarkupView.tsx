import { requireNativeView } from 'expo';
import * as React from 'react';

import { ExpoPdfMarkupViewProps } from './ExpoPdfMarkup.types';

const NativeView: React.ComponentType<ExpoPdfMarkupViewProps> =
  requireNativeView('ExpoPdfMarkup');

export default function ExpoPdfMarkupView(props: ExpoPdfMarkupViewProps) {
  return <NativeView {...props} />;
}
