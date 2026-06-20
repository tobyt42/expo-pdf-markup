import PDFKit
import UIKit

/// Renders an emoji glyph or a local image file as a PDFKit annotation. Data (`contentType`,
/// `emoji`, `imageUri`) round-trips via `setValue(forAnnotationKey:)`, matching the `_id`/`_color`
/// convention in `AnnotationSerializer`, so this subclass stays a pure rendering concern.
final class StampPDFAnnotation: PDFAnnotation {
  private static let contentTypeKey = PDFAnnotationKey(rawValue: "_stampContentType")
  private static let emojiKey = PDFAnnotationKey(rawValue: "_stampEmoji")
  private static let imageUriKey = PDFAnnotationKey(rawValue: "_stampImageUri")

  private static var emojiImageCache: [String: CGImage] = [:]
  private static var fileImageCache: [String: CGImage] = [:]
  private static var failedFilePaths: Set<String> = []

  required init?(coder: NSCoder) {
    super.init(coder: coder)
  }

  override init(bounds: CGRect, forType type: PDFAnnotationSubtype, withProperties properties: [AnyHashable: Any]?) {
    super.init(bounds: bounds, forType: type, withProperties: properties)
  }

  func setStampContentType(_ contentType: String) {
    setValue(contentType, forAnnotationKey: Self.contentTypeKey)
  }

  func setStampEmoji(_ emoji: String) {
    setValue(emoji, forAnnotationKey: Self.emojiKey)
  }

  func setStampImageUri(_ uri: String) {
    setValue(uri, forAnnotationKey: Self.imageUriKey)
  }

  var stampContentType: String? {
    value(forAnnotationKey: Self.contentTypeKey) as? String
  }

  var stampEmoji: String? {
    value(forAnnotationKey: Self.emojiKey) as? String
  }

  var stampImageUri: String? {
    value(forAnnotationKey: Self.imageUriKey) as? String
  }

  override func draw(with _: PDFDisplayBox, in context: CGContext) {
    guard let cgImage = resolveImage() else { return }

    context.saveGState()
    // PDFKit hands draw(with:in:) a raw CGContext already in PDF page space (bottom-up). The
    // CGImage content here (rasterized emoji or a loaded UIImage) is top-down, so without this
    // flip the stamp would render upside down.
    context.translateBy(x: bounds.minX, y: bounds.maxY)
    context.scaleBy(x: 1, y: -1)
    context.draw(cgImage, in: CGRect(origin: .zero, size: bounds.size))
    context.restoreGState()
  }

  private func resolveImage() -> CGImage? {
    switch stampContentType {
    case "emoji":
      guard let emoji = stampEmoji else { return nil }
      return Self.image(forEmoji: emoji)
    case "image":
      guard let uri = stampImageUri else { return nil }
      return Self.image(contentsOfFile: uri)
    default:
      return nil
    }
  }

  private static func image(forEmoji emoji: String) -> CGImage? {
    if let cached = emojiImageCache[emoji] {
      return cached
    }
    let size = CGSize(width: 256, height: 256)
    let renderer = UIGraphicsImageRenderer(size: size)
    let rendered = renderer.image { _ in
      let font = UIFont.systemFont(ofSize: size.height * 0.8)
      let attrs: [NSAttributedString.Key: Any] = [.font: font]
      let textSize = (emoji as NSString).size(withAttributes: attrs)
      let origin = CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2)
      (emoji as NSString).draw(at: origin, withAttributes: attrs)
    }
    guard let cgImage = rendered.cgImage else { return nil }
    emojiImageCache[emoji] = cgImage
    return cgImage
  }

  private static func image(contentsOfFile path: String) -> CGImage? {
    if let cached = fileImageCache[path] {
      return cached
    }
    if failedFilePaths.contains(path) {
      return nil
    }
    guard let cgImage = UIImage(contentsOfFile: path)?.cgImage else {
      failedFilePaths.insert(path)
      return nil
    }
    fileImageCache[path] = cgImage
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
    guard let contentType = stampContentType, stampEmoji != nil || stampImageUri != nil else { return }
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
    model.contentType = contentType
    model.emoji = stampEmoji
    model.imageUri = stampImageUri

    guard let annotation = AnnotationSerializer.toPDFAnnotation(model) else { return }
    page.addAnnotation(annotation)
    emitAnnotationsChanged()
  }
}
