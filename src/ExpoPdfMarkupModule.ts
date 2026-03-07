import { NativeModule, requireNativeModule } from 'expo';

import { ExpoPdfMarkupModuleEvents } from './ExpoPdfMarkup.types';

declare class ExpoPdfMarkupModule extends NativeModule<ExpoPdfMarkupModuleEvents> {
  PI: number;
  hello(): string;
  setValueAsync(value: string): Promise<void>;
}

// This call loads the native module object from the JSI.
export default requireNativeModule<ExpoPdfMarkupModule>('ExpoPdfMarkup');
