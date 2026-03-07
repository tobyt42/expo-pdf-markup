import * as React from 'react';

import { ExpoPdfMarkupViewProps } from './ExpoPdfMarkup.types';

export default function ExpoPdfMarkupView(props: ExpoPdfMarkupViewProps) {
  return (
    <div>
      <iframe
        style={{ flex: 1 }}
        src={props.url}
        onLoad={() => props.onLoad({ nativeEvent: { url: props.url } })}
      />
    </div>
  );
}
