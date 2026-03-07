// Reexport the native module. On web, it will be resolved to ExpoPdfMarkupModule.web.ts
// and on native platforms to ExpoPdfMarkupModule.ts
export { default } from './ExpoPdfMarkupModule';
export { default as ExpoPdfMarkupView } from './ExpoPdfMarkupView';
export * from  './ExpoPdfMarkup.types';
