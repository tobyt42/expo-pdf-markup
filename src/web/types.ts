export type PdfPageMeta = {
  /** PDF page width in PDF user-space points */
  pdfWidth: number;
  /** PDF page height in PDF user-space points */
  pdfHeight: number;
  /** Pixels per PDF point (containerWidth / pdfWidth) */
  scale: number;
  /** Canvas backing width in physical pixels (CSS width × devicePixelRatio) */
  canvasWidth: number;
  /** Canvas backing height in physical pixels (CSS height × devicePixelRatio) */
  canvasHeight: number;
};
