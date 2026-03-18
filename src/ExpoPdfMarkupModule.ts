import { requireNativeModule } from 'expo';

const NativeModule = requireNativeModule('ExpoPdfMarkup');

/**
 * Extracts annotations already embedded in the PDF
 * and returns them serialized as `AnnotationsData` JSON, ready to pass to the `annotations` prop.
 *
 * @param filePath - Path to the PDF file. Accepts both `file://` URIs and bare POSIX paths.
 * @returns A JSON string matching the `AnnotationsData` schema (`{ version: 1, annotations: [...] }`).
 */
export async function getEmbeddedAnnotations(filePath: string): Promise<string> {
  return NativeModule.getEmbeddedAnnotations(filePath);
}
