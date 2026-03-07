import { registerWebModule, NativeModule } from 'expo';

import { ExpoPdfMarkupModuleEvents } from './ExpoPdfMarkup.types';

class ExpoPdfMarkupModule extends NativeModule<ExpoPdfMarkupModuleEvents> {
  PI = Math.PI;
  async setValueAsync(value: string): Promise<void> {
    this.emit('onChange', { value });
  }
  hello() {
    return 'Hello world! 👋';
  }
}

export default registerWebModule(ExpoPdfMarkupModule, 'ExpoPdfMarkupModule');
