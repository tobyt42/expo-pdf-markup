// Jest mock for pdfjs-dist — prevents Worker instantiation errors in test env.

const mockViewport = {
  width: 612,
  height: 792,
};

const mockPage = {
  getViewport: jest.fn().mockReturnValue(mockViewport),
  render: jest.fn().mockReturnValue({ promise: Promise.resolve() }),
  cleanup: jest.fn(),
};

const mockDoc = {
  numPages: 2,
  getPage: jest.fn().mockResolvedValue(mockPage),
  destroy: jest.fn(),
};

export const version = '4.10.38';

export const GlobalWorkerOptions = {
  workerSrc: '',
};

export const getDocument = jest.fn().mockReturnValue({
  promise: Promise.resolve(mockDoc),
});
