import PDFKit

extension ExpoPdfMarkupView {
  // MARK: - Ink drawing

  func setupInkMode() {
    guard inkOverlayView == nil else { return }

    pdfScrollView?.isScrollEnabled = false

    // Disable PDFKit's built-in gesture recognizers (text selection, long-press, etc.)
    // so they don't fire during the touch before a pan gesture would have recognised.
    disabledPdfGestures = pdfView.gestureRecognizers?.filter(\.isEnabled) ?? []
    disabledPdfGestures.forEach { $0.isEnabled = false }

    // Shape layer for live stroke feedback (added to self so it's above pdfView)
    let shape = CAShapeLayer()
    shape.fillColor = nil
    shape.lineCap = .round
    shape.lineJoin = .round
    shape.strokeColor = (AnnotationSerializer.colorFromHex(annotationColor) ?? .red).cgColor
    shape.lineWidth = annotationLineWidth
    shape.frame = bounds
    layer.addSublayer(shape)
    inkShapeLayer = shape

    // Overlay view that captures touches via touchesBegan/Moved/Ended — unlike
    // UIPanGestureRecognizer there is no minimum-distance threshold, so the very
    // first contact point is always recorded.
    let overlay = InkOverlayView(frame: bounds)
    overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    overlay.onBegan = { [weak self] point in
      guard let self else { return }
      inkPoints = [point]
      updateInkShapeLayer()
    }
    overlay.onMoved = { [weak self] point in
      guard let self else { return }
      inkPoints.append(point)
      updateInkShapeLayer()
    }
    overlay.onEnded = { [weak self] point in
      guard let self else { return }
      inkPoints.append(point)
      updateInkShapeLayer()
      finishInkStroke()
    }
    overlay.onCancelled = { [weak self] in
      self?.clearInkStroke()
    }
    addSubview(overlay)
    inkOverlayView = overlay
  }

  func removeInkMode() {
    inkOverlayView?.removeFromSuperview()
    inkOverlayView = nil
    inkShapeLayer?.removeFromSuperlayer()
    inkShapeLayer = nil
    inkPoints = []
    pdfScrollView?.isScrollEnabled = true
    disabledPdfGestures.forEach { $0.isEnabled = true }
    disabledPdfGestures = []
  }

  private func updateInkShapeLayer() {
    let path = UIBezierPath()
    for (index, point) in inkPoints.enumerated() {
      if index == 0 {
        path.move(to: point)
      } else {
        path.addLine(to: point)
      }
    }
    inkShapeLayer?.path = path.cgPath
  }

  private func finishInkStroke() {
    defer { clearInkStroke() }
    guard inkPoints.count >= 2 else { return }

    // Determine which page the stroke is on using the midpoint
    let midPoint = inkPoints[inkPoints.count / 2]
    // Convert display point (in self's coordinate space) to pdfView coordinate space
    let pdfViewMidPoint = pdfView.convert(midPoint, from: self)
    guard let page = pdfView.page(for: pdfViewMidPoint, nearest: true) else { return }

    // Convert all display points to PDF page coordinates
    let pdfPoints = inkPoints.map { displayPoint -> CGPoint in
      let pdfViewPoint = pdfView.convert(displayPoint, from: self)
      return pdfView.convert(pdfViewPoint, to: page)
    }

    // Use the full page bounds — PDFKit clips ink rendering to annotation bounds,
    // and tight bounds calculations are fragile with coordinate transforms.
    let annotationBounds = page.bounds(for: pdfView.displayBox)

    let annotation = PDFAnnotation(bounds: annotationBounds, forType: .ink, withProperties: nil)
    annotation.color = AnnotationSerializer.colorFromHex(annotationColor) ?? .red

    let border = PDFBorder()
    border.lineWidth = annotationLineWidth
    annotation.border = border

    let bezierPath = UIBezierPath()
    for (index, point) in pdfPoints.enumerated() {
      if index == 0 {
        bezierPath.move(to: point)
      } else {
        bezierPath.addLine(to: point)
      }
    }
    annotation.add(bezierPath)

    let id = UUID().uuidString
    AnnotationSerializer.tagAsModuleManaged(annotation, id: id, createdAt: Date().timeIntervalSince1970)
    page.addAnnotation(annotation)

    emitAnnotationsChanged()
  }

  private func clearInkStroke() {
    inkPoints = []
    inkShapeLayer?.path = nil
  }
}

/// Transparent overlay view used in ink mode. Using touchesBegan/Moved/Ended directly
/// avoids the minimum-distance recognition threshold of UIPanGestureRecognizer, ensuring
/// the very first contact point is always captured. coalescedTouches provides all
/// sub-frame samples on high-refresh-rate devices for a more accurate stroke path.
class InkOverlayView: UIView {
  var onBegan: ((CGPoint) -> Void)?
  var onMoved: ((CGPoint) -> Void)?
  var onEnded: ((CGPoint) -> Void)?
  var onCancelled: (() -> Void)?

  private var activeTouch: UITouch?

  override init(frame: CGRect) {
    super.init(frame: frame)
    isMultipleTouchEnabled = true
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func touchesBegan(_ touches: Set<UITouch>, with _: UIEvent?) {
    guard activeTouch == nil else { return }
    // Prefer a pencil touch over a finger so a resting palm doesn't steal the stroke.
    let touch = touches.first(where: { $0.type == .pencil }) ?? touches.first
    guard let touch else { return }
    activeTouch = touch
    onBegan?(touch.location(in: self))
  }

  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard let active = activeTouch, touches.contains(active) else { return }
    for t in event?.coalescedTouches(for: active) ?? [active] {
      onMoved?(t.location(in: self))
    }
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard let active = activeTouch, touches.contains(active) else { return }
    for t in event?.coalescedTouches(for: active) ?? [] {
      onMoved?(t.location(in: self))
    }
    onEnded?(active.location(in: self))
    activeTouch = nil
  }

  override func touchesCancelled(_ touches: Set<UITouch>, with _: UIEvent?) {
    guard let active = activeTouch, touches.contains(active) else { return }
    onCancelled?()
    activeTouch = nil
  }
}
