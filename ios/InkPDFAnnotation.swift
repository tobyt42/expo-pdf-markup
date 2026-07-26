import PDFKit
import UIKit

/// Renders freehand ink strokes as a PDFKit annotation, storing and drawing the stroke
/// geometry itself rather than going through `PDFAnnotation.add(_:)` / `.paths`. iOS 27 beta
/// has a PDFKit regression where those APIs silently drop ink stroke geometry (see report/),
/// so this class sidesteps them entirely — matching the pattern `StampPDFAnnotation` already
/// uses for its own custom-drawn content.
final class InkPDFAnnotation: PDFAnnotation {
  var strokes: [[CGPoint]] = []

  required init?(coder: NSCoder) {
    super.init(coder: coder)
  }

  override init(bounds: CGRect, forType type: PDFAnnotationSubtype, withProperties properties: [AnyHashable: Any]?) {
    super.init(bounds: bounds, forType: type, withProperties: properties)
  }

  override func draw(with _: PDFDisplayBox, in context: CGContext) {
    guard !strokes.isEmpty else { return }

    context.saveGState()
    context.setStrokeColor((color ?? .red).cgColor)
    context.setLineWidth(border?.lineWidth ?? 2.0)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    for stroke in strokes {
      guard let path = Self.cgPath(for: stroke) else { continue }
      context.addPath(path)
    }
    context.strokePath()
    context.restoreGState()
  }

  static func cgPath(for points: [CGPoint]) -> CGPath? {
    guard let first = points.first else { return nil }
    let path = CGMutablePath()
    path.move(to: first)
    for point in points.dropFirst() {
      path.addLine(to: point)
    }
    return path
  }
}
