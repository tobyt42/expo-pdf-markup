import PDFKit
import UIKit

extension ExpoPdfMarkupView {
  /// Area input works on scanned and selectable pages alike. Navigation is explicit:
  /// leave the tool for touch scrolling/zoom, or use the page prop/book hardware keys.
  func setupAreaMarkupMode() {
    guard markupOverlayView == nil else { return }
    markupScrollWasEnabled = pdfScrollView?.isScrollEnabled
    pdfScrollView?.isScrollEnabled = false
    markupDisabledGestures = pdfView.gestureRecognizers?.filter(\.isEnabled) ?? []
    markupDisabledGestures.forEach { $0.isEnabled = false }
    pdfView.clearSelection()

    let overlay = InkOverlayView(frame: bounds)
    overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    let preview = CAShapeLayer()
    overlay.layer.addSublayer(preview)
    markupPreviewLayer = preview
    overlay.onBegan = { [weak self] in self?.beginAreaMarkup(at: $0) }
    overlay.onMoved = { [weak self] in self?.updateAreaMarkup(at: $0) }
    overlay.onEnded = { [weak self] in self?.finishAreaMarkup() }
    overlay.onCancelled = { [weak self] in self?.cancelAreaMarkup() }
    addSubview(overlay)
    markupOverlayView = overlay
  }

  func removeAreaMarkupMode() {
    cancelAreaMarkup()
    markupOverlayView?.removeFromSuperview()
    markupOverlayView = nil
    markupPreviewLayer = nil
    if let wasEnabled = markupScrollWasEnabled { pdfScrollView?.isScrollEnabled = wasEnabled }
    markupScrollWasEnabled = nil
    markupDisabledGestures.forEach { $0.isEnabled = true }
    markupDisabledGestures = []
  }

  func cancelAreaMarkup() {
    markupPage = nil
    markupStartPoint = nil
    markupEndPoint = nil
    markupPreviewLayer?.path = nil
  }

  private func beginAreaMarkup(at point: CGPoint) {
    cancelAreaMarkup()
    let location = pdfView.convert(point, from: self)
    guard let page = pdfView.page(for: location, nearest: false) else { return }
    let coordinates = AnnotationCoordinates(page: page)
    let visible = pdfView.convert(location, to: page).applying(coordinates.nativeToVisible)
    guard coordinates.visibleBounds.contains(visible) else { return }
    markupPage = page
    markupStartPoint = visible
    markupEndPoint = visible
  }

  private func updateAreaMarkup(at point: CGPoint) {
    guard let page = markupPage, page.document === pdfView.document else { return }
    let coordinates = AnnotationCoordinates(page: page)
    let visible = pdfView.convert(pdfView.convert(point, from: self), to: page)
      .applying(coordinates.nativeToVisible)
    let bounds = coordinates.visibleBounds
    markupEndPoint = CGPoint(x: min(max(visible.x, bounds.minX), bounds.maxX),
                             y: min(max(visible.y, bounds.minY), bounds.maxY))
    guard let area = areaMarkupBounds else { return }
    let native = area.applying(coordinates.visibleToNative)
    let display = convert(pdfView.convert(native, from: page), from: pdfView)
    let path = UIBezierPath()
    let color = AnnotationSerializer.colorFromHex(annotationColor) ?? .red
    if currentMode == "highlight" {
      path.append(UIBezierPath(rect: display))
      markupPreviewLayer?.fillColor = color.withAlphaComponent(0.5).cgColor
      markupPreviewLayer?.strokeColor = nil
    } else {
      path.move(to: CGPoint(x: display.minX, y: display.maxY))
      path.addLine(to: CGPoint(x: display.maxX, y: display.maxY))
      markupPreviewLayer?.fillColor = nil
      markupPreviewLayer?.strokeColor = color.cgColor
      markupPreviewLayer?.lineWidth = AreaUnderlinePDFAnnotation.strokeWidth * pdfView.scaleFactor
    }
    markupPreviewLayer?.path = path.cgPath
  }

  private var areaMarkupBounds: CGRect? {
    guard let start = markupStartPoint, let end = markupEndPoint else { return nil }
    return CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                  width: abs(end.x - start.x), height: abs(end.y - start.y))
  }

  private func finishAreaMarkup() {
    defer { cancelAreaMarkup() }
    guard currentMode == "highlight" || currentMode == "underline",
          let page = markupPage, page.document === pdfView.document,
          let bounds = areaMarkupBounds, bounds.width > 1, bounds.height > 1 else { return }
    let model = AnnotationModel(id: UUID().uuidString, type: currentMode,
                                page: pdfView.document?.index(for: page) ?? 0, color: annotationColor,
                                alpha: currentMode == "highlight" ? 0.5 : nil,
                                bounds: AnnotationBounds(bounds), createdAt: Date().timeIntervalSince1970)
    guard let annotation = AnnotationSerializer.toPDFAnnotation(
      model, pageBounds: page.bounds(for: .cropBox), pageRotation: page.rotation
    ) else { return }
    page.addAnnotation(annotation)
    emitAnnotationsChanged()
  }
}

/// PDFKit's built-in underline offsets its stroke toward native page-up. On rotated
/// pages that can select the wrong edge or put the line outside the crop box.
/// Drawing the visible rectangle's lower edge also keeps edit and hit geometry aligned.
final class AreaUnderlinePDFAnnotation: PDFAnnotation {
  static let strokeWidth: CGFloat = 2

  required init?(coder: NSCoder) {
    super.init(coder: coder)
  }

  override init(bounds: CGRect, forType type: PDFAnnotationSubtype, withProperties properties: [AnyHashable: Any]?) {
    super.init(
      bounds: bounds.insetBy(
        dx: -AnnotationCoordinates.appearancePadding,
        dy: -AnnotationCoordinates.appearancePadding
      ),
      forType: type,
      withProperties: properties
    )
  }

  var contentBounds: CGRect {
    bounds.insetBy(dx: AnnotationCoordinates.appearancePadding, dy: AnnotationCoordinates.appearancePadding)
  }

  var renderedBounds: CGRect {
    contentBounds.insetBy(dx: -Self.strokeWidth / 2, dy: -Self.strokeWidth / 2)
  }

  override func draw(with box: PDFDisplayBox, in context: CGContext) {
    let coordinates = page.map {
      AnnotationCoordinates(bounds: $0.bounds(for: box), rotation: $0.rotation)
    } ?? AnnotationCoordinates(bounds: .zero)
    let visible = contentBounds.applying(coordinates.nativeToVisible)
    context.saveGState()
    coordinates.prepareForDrawing(in: context, annotationBounds: bounds)
    context.setStrokeColor(color.cgColor)
    context.setLineWidth(Self.strokeWidth)
    context.move(to: CGPoint(x: visible.minX, y: visible.minY))
    context.addLine(to: CGPoint(x: visible.maxX, y: visible.minY))
    context.strokePath()
    context.restoreGState()
  }
}
