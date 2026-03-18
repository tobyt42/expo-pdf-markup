import * as ExportedModule from '../index';

jest.mock('expo', () => ({
  requireNativeView: jest.fn(() => 'MockNativeView'),
  requireNativeModule: jest.fn(() => ({
    provideTextInput: jest.fn(),
    getEmbeddedAnnotations: jest.fn().mockResolvedValue('{"version":1,"annotations":[]}'),
  })),
}));

describe('public API surface', () => {
  it('exports ExpoPdfMarkupView as a function', () => {
    expect(typeof ExportedModule.ExpoPdfMarkupView).toBe('function');
  });

  it('does not leak unexpected exports', () => {
    const exportedKeys = Object.keys(ExportedModule);
    expect(exportedKeys).toContain('ExpoPdfMarkupView');
    const nonTypeExports = exportedKeys.filter(
      (k) => typeof (ExportedModule as any)[k] !== 'undefined'
    );
    expect(nonTypeExports).toEqual([
      'ExpoPdfMarkupView',
      'setPdfJsWorkerSrc',
      'getEmbeddedAnnotations',
    ]);
  });
});
