const mockNativeModule = {
  provideTextInput: jest.fn(),
  getEmbeddedAnnotations: jest
    .fn()
    .mockResolvedValue(
      '{"version":1,"annotations":[{"id":"a1","type":"ink","page":0,"color":"#FF0000","lineWidth":2,"paths":[],"createdAt":1000}]}'
    ),
};

jest.mock('expo', () => ({
  requireNativeView: jest.fn(() => 'MockNativeView'),
  requireNativeModule: jest.fn(() => mockNativeModule),
}));

import { getEmbeddedAnnotations } from '../ExpoPdfMarkupModule';

describe('getEmbeddedAnnotations (native)', () => {
  it('calls native module with the provided file path', async () => {
    await getEmbeddedAnnotations('/path/to/file.pdf');
    expect(mockNativeModule.getEmbeddedAnnotations).toHaveBeenCalledWith('/path/to/file.pdf');
  });

  it('returns the resolved value from the native module', async () => {
    const result = await getEmbeddedAnnotations('/path/to/file.pdf');
    const parsed = JSON.parse(result);
    expect(parsed.version).toBe(1);
    expect(parsed.annotations).toHaveLength(1);
    expect(parsed.annotations[0].type).toBe('ink');
  });
});
