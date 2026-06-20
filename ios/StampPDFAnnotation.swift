import PDFKit
import UIKit

/// Renders a text glyph (e.g. an emoji, or a plain character like `"f"`) as a PDFKit annotation.
/// Data (`text`) round-trips via `setValue(forAnnotationKey:)`, matching the `_id`/`_color`
/// convention in `AnnotationSerializer`, so this subclass stays a pure rendering concern.
final class StampPDFAnnotation: PDFAnnotation {
  private static let textKey = PDFAnnotationKey(rawValue: "_stampText")

  private static var textImageCache: [String: CGImage] = [:]

  required init?(coder: NSCoder) {
    super.init(coder: coder)
  }

  override init(bounds: CGRect, forType type: PDFAnnotationSubtype, withProperties properties: [AnyHashable: Any]?) {
    super.init(bounds: bounds, forType: type, withProperties: properties)
  }

  func setStampText(_ text: String) {
    setValue(text, forAnnotationKey: Self.textKey)
  }

  var stampText: String? {
    value(forAnnotationKey: Self.textKey) as? String
  }

  override func draw(with _: PDFDisplayBox, in context: CGContext) {
    guard let text = stampText, let cgImage = Self.image(forText: text) else { return }

    context.saveGState()
    // PDFKit hands draw(with:in:) a raw CGContext already in PDF page space (bottom-up). The
    // rasterized text image here is top-down, so without this flip the stamp would render
    // upside down.
    context.translateBy(x: bounds.minX, y: bounds.maxY)
    context.scaleBy(x: 1, y: -1)
    context.draw(cgImage, in: CGRect(origin: .zero, size: bounds.size))
    context.restoreGState()
  }

  private static func image(forText text: String) -> CGImage? {
    if let cached = textImageCache[text] {
      return cached
    }
    let size = CGSize(width: 256, height: 256)
    let renderer = UIGraphicsImageRenderer(size: size)
    let rendered = renderer.image { _ in
      let font = UIFont.systemFont(ofSize: size.height * 0.8)
      let attrs: [NSAttributedString.Key: Any] = [.font: font]
      let textSize = (text as NSString).size(withAttributes: attrs)
      let origin = CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2)
      (text as NSString).draw(at: origin, withAttributes: attrs)
    }
    guard let cgImage = rendered.cgImage else { return nil }
    textImageCache[text] = cgImage
    return cgImage
  }
}

extension ExpoPdfMarkupView {
  // MARK: - Stamp

  func setupStampGesture() {
    guard stampTapGesture == nil else { return }
    let tap = UITapGestureRecognizer(target: self, action: #selector(handleStampTap(_:)))
    tap.delegate = self
    pdfView.addGestureRecognizer(tap)
    stampTapGesture = tap
  }

  func removeStampGesture() {
    if let gesture = stampTapGesture {
      pdfView.removeGestureRecognizer(gesture)
      stampTapGesture = nil
    }
  }

  @objc func handleStampTap(_ gesture: UITapGestureRecognizer) {
    guard let text = stampText else { return }
    let location = gesture.location(in: pdfView)
    guard let page = pdfView.page(for: location, nearest: true) else { return }
    let pdfPoint = pdfView.convert(location, to: page)

    let half = stampSize / 2
    var model = AnnotationModel(
      id: UUID().uuidString,
      type: "stamp",
      page: 0,
      color: "#000000",
      createdAt: Date().timeIntervalSince1970
    )
    model.bounds = AnnotationBounds(
      CGRect(x: pdfPoint.x - half, y: pdfPoint.y - half, width: stampSize, height: stampSize)
    )
    model.text = text

    guard let annotation = AnnotationSerializer.toPDFAnnotation(model) else { return }
    page.addAnnotation(annotation)
    emitAnnotationsChanged()
  }
}
