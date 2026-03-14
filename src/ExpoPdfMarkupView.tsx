import { requireNativeModule, requireNativeView } from 'expo';
import * as React from 'react';
import { findNodeHandle } from 'react-native';

import { ExpoPdfMarkupViewProps, TextInputRequest } from './ExpoPdfMarkup.types';

type NativeViewProps = Omit<ExpoPdfMarkupViewProps, 'onTextInputRequested'> & {
  useJsTextDialog?: boolean;
  onTextInputRequested?: (event: { nativeEvent: TextInputRequest }) => void;
};

const NativeView = requireNativeView('ExpoPdfMarkup') as React.ForwardRefExoticComponent<
  NativeViewProps & React.RefAttributes<unknown>
>;

const NativeModule = requireNativeModule('ExpoPdfMarkup');

export default function ExpoPdfMarkupView({
  onTextInputRequested,
  ...props
}: ExpoPdfMarkupViewProps) {
  const nativeRef = React.useRef<unknown>(null);

  const handleNativeTextInputRequested = React.useCallback(
    async (event: { nativeEvent: TextInputRequest }) => {
      if (!onTextInputRequested) return;
      const tag = findNodeHandle(nativeRef.current as Parameters<typeof findNodeHandle>[0]);
      if (tag == null) return;
      const text = await onTextInputRequested(event.nativeEvent);
      await NativeModule.provideTextInput(tag, text ?? null);
    },
    [onTextInputRequested]
  );

  return (
    <NativeView
      ref={nativeRef}
      {...props}
      useJsTextDialog={!!onTextInputRequested}
      onTextInputRequested={onTextInputRequested ? handleNativeTextInputRequested : undefined}
    />
  );
}
