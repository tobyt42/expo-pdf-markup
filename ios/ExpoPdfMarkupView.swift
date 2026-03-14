import ExpoModulesCore
import PDFKit

class ExpoPdfMarkupView: ExpoView, UIGestureRecognizerDelegate {
  let pdfView = PDFView()
  let onPageChanged = EventDispatcher()
  let onLoadComplete = EventDispatcher()
  let onError = EventDispatcher()
  let onAnnotationsChanged = EventDispatcher()
  let onTextInputRequested = EventDispatcher()

  private var currentSource: String?
  private var currentAnnotationsJSON: String?
  private var currentMode: String = "none"
  var annotationColor: String = "#FF0000" {
    didSet {
      inkShapeLayer?.strokeColor = (AnnotationSerializer.colorFromHex(annotationColor) ?? .red).cgColor
    }
  }

  var annotationLineWidth: CGFloat = 2.0
  var annotationFontFamily: String?
  var useJsTextDialog: Bool = false

  private var inkPanGesture: UIPanGestureRecognizer?
  private var inkShapeLayer: CAShapeLayer?
  private var inkPoints: [CGPoint] = []
  private var eraserTapGesture: UITapGestureRecognizer?
  private var movePanGesture: UIPanGestureRecognizer?
  private var editingOverlayLayer: CAShapeLayer?
  var textTapGesture: UITapGestureRecognizer?
  private var selectionObserver: NSObjectProtocol?
  private var selectionDebounceTimer: Timer?
  private var currentMarkupType: String?
  private var movingPage: PDFPage?
  private var movingOriginalModel: AnnotationModel?
  private var movingPreviewModel: AnnotationModel?
  private var movingPreviewAnnotation: PDFAnnotation?
  private var moveStartPoint: CGPoint?

  var pendingTextPage: PDFPage?
  var pendingTextPoint: CGPoint?
  var pendingTextAnnotation: PDFAnnotation?

  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    clipsToBounds = true

    pdfView.autoScales = true
    pdfView.displayMode = .singlePageContinuous
    pdfView.displayDirection = .vertical
    pdfView.pageBreakMargins = UIEdgeInsets(top: 0, left: 0, bottom: 8, right: 0)
    pdfView.backgroundColor = UIColor(white: 0.92, alpha: 1)

    addSubview(pdfView)

    if let scrollView = pdfView.subviews.first(where: { $0 is UIScrollView }) as? UIScrollView {
      scrollView.contentInsetAdjustmentBehavior = .never
    }

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handlePageChanged),
      name: .PDFViewPageChanged,
      object: pdfView
    )
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
    if let selectionObserver {
      NotificationCenter.default.removeObserver(selectionObserver)
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    pdfView.frame = bounds
    inkShapeLayer?.frame = bounds
    editingOverlayLayer?.frame = pdfView.documentView?.bounds ?? .zero
    updateEditingOverlay()
  }

  // MARK: - Props

  func setBackgroundColor(_ color: UIColor?) {
    pdfView.backgroundColor = color ?? UIColor(white: 0.92, alpha: 1)
  }

  func loadPdf(from source: String) {
    guard source != currentSource else { return }
    currentSource = source

    let fileURL = URL(fileURLWithPath: source)
    guard let document = PDFDocument(url: fileURL) else {
      onError(["message": "Failed to load PDF from: \(source)"])
      return
    }

    pdfView.document = document
    let pageCount = document.pageCount
    onLoadComplete(["pageCount": pageCount])

    // Re-apply annotations if we have them
    if let json = currentAnnotationsJSON {
      currentAnnotationsJSON = nil
      loadAnnotations(from: json)
    } else {
      updateEditingOverlay()
    }
  }

  func goToPage(_ pageIndex: Int) {
    guard let document = pdfView.document else { return }
    guard pageIndex >= 0, pageIndex < document.pageCount else { return }
    guard let page = document.page(at: pageIndex) else { return }

    if let currentPage = pdfView.currentPage, document.index(for: currentPage) == pageIndex {
      return
    }

    pdfView.go(to: page)
  }

  // MARK: - Annotation management

  func loadAnnotations(from json: String?) {
    guard let json, !json.isEmpty else {
      clearModuleManagedAnnotations()
      currentAnnotationsJSON = nil
      updateEditingOverlay()
      return
    }

    guard json != currentAnnotationsJSON else { return }
    currentAnnotationsJSON = json

    guard let document = pdfView.document else { return }

    clearModuleManagedAnnotations()

    guard let data = AnnotationSerializer.deserialize(from: json) else { return }

    for model in data.annotations {
      guard model.page >= 0, model.page < document.pageCount else { continue }
      guard let page = document.page(at: model.page) else { continue }
      let pageBounds = page.bounds(for: pdfView.displayBox)
      guard let pdfAnnotation = AnnotationSerializer.toPDFAnnotation(model, pageBounds: pageBounds) else {
        continue
      }
      page.addAnnotation(pdfAnnotation)
    }

    updateEditingOverlay()
  }

  func serializeCurrentAnnotations() -> String {
    guard let document = pdfView.document else {
      return "{\"version\":1,\"annotations\":[]}"
    }

    var models: [AnnotationModel] = []
    for pageIndex in 0 ..< document.pageCount {
      guard let page = document.page(at: pageIndex) else { continue }
      for annotation in page.annotations {
        if let model = AnnotationSerializer.toModel(from: annotation, page: pageIndex) {
          models.append(model)
        }
      }
    }

    let data = AnnotationsData(version: 1, annotations: models)
    return AnnotationSerializer.serialize(data) ?? "{\"version\":1,\"annotations\":[]}"
  }

  func emitAnnotationsChanged() {
    let json = serializeCurrentAnnotations()
    currentAnnotationsJSON = json
    onAnnotationsChanged(["annotations": json])
    updateEditingOverlay()
  }

  private func clearModuleManagedAnnotations() {
    guard let document = pdfView.document else { return }
    for pageIndex in 0 ..< document.pageCount {
      guard let page = document.page(at: pageIndex) else { continue }
      let toRemove = page.annotations.filter { AnnotationSerializer.isModuleManaged($0) }
      for annotation in toRemove {
        page.removeAnnotation(annotation)
      }
    }
    updateEditingOverlay()
  }

  // MARK: - Annotation mode

  func setAnnotationMode(_ mode: String) {
    let previousMode = currentMode
    currentMode = mode

    // Clean up previous mode
    if previousMode != mode {
      removeInkMode()
      removeEraserGesture()
      removeMoveMode()
      removeTextGesture()
      removeSelectionObserver()
    }

    switch mode {
    case "ink":
      setupInkMode()
    case "eraser":
      setupEraserGesture()
    case "move":
      setupMoveMode()
    case "highlight", "underline":
      setupSelectionObserver(markupType: mode)
    case "text":
      setupTextGesture()
    default:
      break
    }

    updateEditingOverlay()
  }

  // MARK: - Ink drawing

  private var pdfScrollView: UIScrollView? {
    pdfView.subviews.first(where: { $0 is UIScrollView }) as? UIScrollView
  }

  private func setupInkMode() {
    guard inkPanGesture == nil else { return }

    // Disable scrolling so pan gestures go to our recognizer, not the scroll view
    pdfScrollView?.isScrollEnabled = false

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

    // Pan gesture on pdfView — points come in pdfView's coordinate space
    let pan = UIPanGestureRecognizer(target: self, action: #selector(handleInkPan(_:)))
    pan.maximumNumberOfTouches = 1
    pdfView.addGestureRecognizer(pan)
    inkPanGesture = pan
  }

  private func removeInkMode() {
    if let gesture = inkPanGesture {
      pdfView.removeGestureRecognizer(gesture)
      inkPanGesture = nil
    }
    inkShapeLayer?.removeFromSuperlayer()
    inkShapeLayer = nil
    inkPoints = []
    pdfScrollView?.isScrollEnabled = true
  }

  @objc private func handleInkPan(_ gesture: UIPanGestureRecognizer) {
    // Get point in self's coordinate space for visual feedback
    let displayPoint = gesture.location(in: self)

    switch gesture.state {
    case .began:
      inkPoints = [displayPoint]
      updateInkShapeLayer()
    case .changed:
      inkPoints.append(displayPoint)
      updateInkShapeLayer()
    case .ended:
      inkPoints.append(displayPoint)
      updateInkShapeLayer()
      finishInkStroke()
    case .cancelled, .failed:
      clearInkStroke()
    default:
      break
    }
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

  // MARK: - Eraser

  private func setupEraserGesture() {
    guard eraserTapGesture == nil else { return }
    let tap = UITapGestureRecognizer(target: self, action: #selector(handleEraserTap(_:)))
    tap.delegate = self
    pdfView.addGestureRecognizer(tap)
    eraserTapGesture = tap
  }

  private func removeEraserGesture() {
    if let gesture = eraserTapGesture {
      pdfView.removeGestureRecognizer(gesture)
      eraserTapGesture = nil
    }
  }

  @objc private func handleEraserTap(_ gesture: UITapGestureRecognizer) {
    let location = gesture.location(in: pdfView)
    guard let page = pdfView.page(for: location, nearest: true) else { return }

    let pdfPoint = pdfView.convert(location, to: page)

    // Use path-based hit testing — page.annotation(at:) only checks bounds rect,
    // which is the full page for our ink annotations. Instead, test each annotation's
    // actual path with a stroke tolerance.
    if let annotation = hitTestAnnotation(at: pdfPoint, on: page) {
      page.removeAnnotation(annotation)
      emitAnnotationsChanged()
    }
  }

  private func hitTestAnnotation(at point: CGPoint, on page: PDFPage) -> PDFAnnotation? {
    for annotation in page.annotations.reversed() {
      guard AnnotationSerializer.isModuleManaged(annotation) else { continue }

      // For ink annotations, test against the actual paths
      if let paths = annotation.paths {
        let tolerance = max(annotation.border?.lineWidth ?? 2.0, 10.0)
        for path in paths {
          let hitPath = path.cgPath.copy(
            strokingWithWidth: tolerance,
            lineCap: .round,
            lineJoin: .round,
            miterLimit: 0
          )
          if hitPath.contains(point) {
            return annotation
          }
        }
      } else if annotation.bounds.contains(point) {
        // For non-ink annotations (highlight, underline, text), bounds check is fine
        return annotation
      }
    }
    return nil
  }

  // MARK: - Highlight / Underline

  private func setupSelectionObserver(markupType: String) {
    guard selectionObserver == nil else { return }
    currentMarkupType = markupType

    // Observe selection changes with a debounce — the notification fires continuously
    // during drag. We wait for the selection to settle before creating the annotation.
    selectionObserver = NotificationCenter.default.addObserver(
      forName: .PDFViewSelectionChanged,
      object: pdfView,
      queue: .main
    ) { [weak self] _ in
      self?.scheduleSelectionHandler()
    }
  }

  private func removeSelectionObserver() {
    selectionDebounceTimer?.invalidate()
    selectionDebounceTimer = nil
    currentMarkupType = nil
    if let observer = selectionObserver {
      NotificationCenter.default.removeObserver(observer)
      selectionObserver = nil
    }
    pdfView.clearSelection()
  }

  private func scheduleSelectionHandler() {
    selectionDebounceTimer?.invalidate()
    selectionDebounceTimer = Timer.scheduledTimer(
      withTimeInterval: 0.5,
      repeats: false
    ) { [weak self] _ in
      self?.applyMarkupToSelection()
    }
  }

  private func applyMarkupToSelection() {
    guard let markupType = currentMarkupType else { return }
    guard let selection = pdfView.currentSelection else { return }
    let selectionsByPage = selection.selectionsByLine()

    var didAdd = false
    for lineSelection in selectionsByPage {
      guard let page = lineSelection.pages.first else { continue }
      let bounds = lineSelection.bounds(for: page)
      guard bounds.width > 0, bounds.height > 0 else { continue }

      let subtype: PDFAnnotationSubtype = markupType == "highlight" ? .highlight : .underline
      let annotation = PDFAnnotation(bounds: bounds, forType: subtype, withProperties: nil)
      let color = AnnotationSerializer.colorFromHex(annotationColor) ?? .yellow
      annotation.color = markupType == "highlight" ? color.withAlphaComponent(0.5) : color

      let id = UUID().uuidString
      AnnotationSerializer.tagAsModuleManaged(annotation, id: id, createdAt: Date().timeIntervalSince1970)
      page.addAnnotation(annotation)
      didAdd = true
    }

    if didAdd {
      pdfView.clearSelection()
      emitAnnotationsChanged()
    }
  }

  // MARK: - UIGestureRecognizerDelegate

  func gestureRecognizer(
    _: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
  ) -> Bool {
    true
  }

  // MARK: - Page change notification

  @objc private func handlePageChanged() {
    guard let document = pdfView.document,
          let currentPage = pdfView.currentPage else { return }

    let pageIndex = document.index(for: currentPage)
    let pageCount = document.pageCount
    let bounds = currentPage.bounds(for: pdfView.displayBox)
    onPageChanged([
      "page": pageIndex,
      "pageCount": pageCount,
      "pageWidth": bounds.width,
      "pageHeight": bounds.height,
    ])
    updateEditingOverlay()
  }
}

extension ExpoPdfMarkupView {
  // MARK: - Move

  func setupMoveMode() {
    guard movePanGesture == nil else { return }
    pdfScrollView?.isScrollEnabled = false
    let pan = UIPanGestureRecognizer(target: self, action: #selector(handleMovePan(_:)))
    pan.maximumNumberOfTouches = 1
    pan.delegate = self
    pdfView.addGestureRecognizer(pan)
    movePanGesture = pan
  }

  func removeMoveMode() {
    if let gesture = movePanGesture {
      pdfView.removeGestureRecognizer(gesture)
      movePanGesture = nil
    }
    finishMove(commit: false)
    pdfScrollView?.isScrollEnabled = true
  }

  @objc func handleMovePan(_ gesture: UIPanGestureRecognizer) {
    switch gesture.state {
    case .began:
      beginMove(at: gesture.location(in: pdfView))
    case .changed:
      updateMove(at: gesture.location(in: pdfView))
    case .ended:
      finishMove(commit: true)
    case .cancelled, .failed:
      finishMove(commit: false)
    default:
      break
    }
  }

  private func beginMove(at location: CGPoint) {
    guard let document = pdfView.document,
          let page = pdfView.page(for: location, nearest: true) else { return }

    let pdfPoint = pdfView.convert(location, to: page)
    guard let annotation = hitTestAnnotation(at: pdfPoint, on: page) else { return }

    let pageIndex = document.index(for: page)
    guard let model = AnnotationSerializer.toModel(from: annotation, page: pageIndex),
          let preview = annotationForModel(model, on: page) else { return }

    movingPage = page
    movingOriginalModel = model
    movingPreviewModel = model
    moveStartPoint = pdfPoint

    page.removeAnnotation(annotation)
    page.addAnnotation(preview)
    movingPreviewAnnotation = preview
    updateEditingOverlay()
  }

  private func updateMove(at location: CGPoint) {
    guard let page = movingPage,
          let originalModel = movingOriginalModel,
          let startPoint = moveStartPoint else { return }

    let pdfPoint = pdfView.convert(location, to: page)
    let rawDeltaX = pdfPoint.x - startPoint.x
    let rawDeltaY = pdfPoint.y - startPoint.y
    let clampedDelta = clampedTranslation(for: originalModel, dx: rawDeltaX, dy: rawDeltaY, on: page)
    let translatedModel = translatedModel(originalModel, dx: clampedDelta.x, dy: clampedDelta.y)
    guard translatedModel != movingPreviewModel,
          let replacement = annotationForModel(translatedModel, on: page) else { return }

    if let currentPreview = movingPreviewAnnotation {
      page.removeAnnotation(currentPreview)
    }
    page.addAnnotation(replacement)
    movingPreviewAnnotation = replacement
    movingPreviewModel = translatedModel
    updateEditingOverlay()
  }

  private func finishMove(commit: Bool) {
    guard let page = movingPage,
          let originalModel = movingOriginalModel else {
      clearMoveState()
      updateEditingOverlay()
      return
    }

    if let preview = movingPreviewAnnotation {
      page.removeAnnotation(preview)
    }

    let finalModel = commit ? (movingPreviewModel ?? originalModel) : originalModel
    if let finalAnnotation = annotationForModel(finalModel, on: page) {
      page.addAnnotation(finalAnnotation)
    }

    let didChange = commit && finalModel != originalModel
    clearMoveState()
    updateEditingOverlay()

    if didChange {
      emitAnnotationsChanged()
    }
  }

  private func clearMoveState() {
    movingPage = nil
    movingOriginalModel = nil
    movingPreviewModel = nil
    movingPreviewAnnotation = nil
    moveStartPoint = nil
  }

  // MARK: - Editing overlay

  func updateEditingOverlay() {
    guard currentMode == "move" || currentMode == "eraser" else {
      editingOverlayLayer?.removeFromSuperlayer()
      editingOverlayLayer = nil
      return
    }

    guard let document = pdfView.document,
          let documentView = pdfView.documentView else { return }

    let overlay = editingOverlayLayer ?? {
      let shape = CAShapeLayer()
      shape.fillColor = UIColor.clear.cgColor
      shape.strokeColor = UIColor.systemBlue.cgColor
      shape.lineWidth = 1.5
      shape.lineDashPattern = [6, 4]
      documentView.layer.addSublayer(shape)
      editingOverlayLayer = shape
      return shape
    }()

    if overlay.superlayer !== documentView.layer {
      overlay.removeFromSuperlayer()
      documentView.layer.addSublayer(overlay)
    }

    overlay.frame = documentView.bounds
    let path = UIBezierPath()

    for pageIndex in 0 ..< document.pageCount {
      guard let page = document.page(at: pageIndex) else { continue }
      for annotation in page.annotations where AnnotationSerializer.isModuleManaged(annotation) {
        guard let outlineRect = annotationOutlineRect(for: annotation, on: page, in: documentView) else {
          continue
        }
        path.append(UIBezierPath(rect: outlineRect))
      }
    }

    overlay.path = path.cgPath
  }

  private func annotationOutlineRect(
    for annotation: PDFAnnotation,
    on page: PDFPage,
    in documentView: UIView
  ) -> CGRect? {
    let pdfRect: CGRect
    if let paths = annotation.paths, !paths.isEmpty {
      var combinedBounds = CGRect.null
      for path in paths {
        combinedBounds = combinedBounds.union(path.cgPath.boundingBoxOfPath)
      }
      guard !combinedBounds.isNull else { return nil }
      let padding = max(annotation.border?.lineWidth ?? 2.0, 10.0)
      pdfRect = combinedBounds.insetBy(dx: -padding, dy: -padding)
    } else {
      pdfRect = annotation.bounds
    }

    let pdfViewRect = pdfView.convert(pdfRect, from: page)
    return documentView.convert(pdfViewRect, from: pdfView)
  }

  private func annotationForModel(_ model: AnnotationModel, on page: PDFPage) -> PDFAnnotation? {
    AnnotationSerializer.toPDFAnnotation(model, pageBounds: page.bounds(for: pdfView.displayBox))
  }

  private func translatedModel(_ model: AnnotationModel, dx: CGFloat, dy: CGFloat) -> AnnotationModel {
    guard dx != 0 || dy != 0 else { return model }

    var updated = model
    switch model.type {
    case "ink":
      let translatedPaths = model.decodedPaths.map { stroke in
        stroke.map { point in
          AnnotationPoint(x: point.x + dx, y: point.y + dy)
        }
      }
      updated.paths = updated.encodedPaths(from: translatedPaths)
    case "highlight", "underline", "text", "freeText":
      if let bounds = model.bounds {
        updated.bounds = AnnotationBounds(
          x: bounds.x + dx,
          y: bounds.y + dy,
          width: bounds.width,
          height: bounds.height
        )
      }
    default:
      break
    }
    return updated
  }

  private func clampedTranslation(
    for model: AnnotationModel,
    dx: CGFloat,
    dy: CGFloat,
    on page: PDFPage
  ) -> CGPoint {
    guard let outlineBounds = annotationOutlineBounds(for: model) else {
      return CGPoint(x: dx, y: dy)
    }

    let pageBounds = page.bounds(for: pdfView.displayBox)
    let minDx = pageBounds.minX - outlineBounds.x
    let maxDx = pageBounds.maxX - (outlineBounds.x + outlineBounds.width)
    let minDy = pageBounds.minY - outlineBounds.y
    let maxDy = pageBounds.maxY - (outlineBounds.y + outlineBounds.height)

    return CGPoint(
      x: min(max(dx, minDx), maxDx),
      y: min(max(dy, minDy), maxDy)
    )
  }

  private func annotationOutlineBounds(for model: AnnotationModel) -> AnnotationBounds? {
    guard model.type == "ink" else { return model.bounds }
    let paths = model.decodedPaths
    var minX = CGFloat.greatestFiniteMagnitude
    var minY = CGFloat.greatestFiniteMagnitude
    var maxX = -CGFloat.greatestFiniteMagnitude
    var maxY = -CGFloat.greatestFiniteMagnitude

    for stroke in paths {
      for point in stroke {
        minX = min(minX, point.x)
        minY = min(minY, point.y)
        maxX = max(maxX, point.x)
        maxY = max(maxY, point.y)
      }
    }

    guard minX.isFinite, minY.isFinite, maxX.isFinite, maxY.isFinite else { return nil }

    let padding = max(model.lineWidth ?? 2.0, 10.0)
    return AnnotationBounds(
      x: minX - padding,
      y: minY - padding,
      width: maxX - minX + padding * 2,
      height: maxY - minY + padding * 2
    )
  }
}
