import ExpoModulesCore
import PDFKit

class ExpoPdfMarkupView: ExpoView, UIGestureRecognizerDelegate {
  let pdfView = PDFView()
  let onPageChanged = EventDispatcher()
  let onLoadComplete = EventDispatcher()
  let onError = EventDispatcher()
  let onAnnotationsChanged = EventDispatcher()

  private var currentSource: String?
  private var currentAnnotationsJSON: String?
  private var currentMode: String = "none"
  var annotationColor: String = "#FF0000"
  var annotationLineWidth: CGFloat = 2.0

  private var inkPanGesture: UIPanGestureRecognizer?
  private var inkShapeLayer: CAShapeLayer?
  private var inkPoints: [CGPoint] = []
  private var eraserTapGesture: UITapGestureRecognizer?
  private var textTapGesture: UITapGestureRecognizer?
  private var selectionObserver: NSObjectProtocol?
  private var selectionDebounceTimer: Timer?
  private var currentMarkupType: String?

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
  }

  // MARK: - Annotation mode

  func setAnnotationMode(_ mode: String) {
    let previousMode = currentMode
    currentMode = mode

    // Clean up previous mode
    if previousMode != mode {
      removeInkMode()
      removeEraserGesture()
      removeTextGesture()
      removeSelectionObserver()
    }

    switch mode {
    case "ink":
      setupInkMode()
    case "eraser":
      setupEraserGesture()
    case "highlight", "underline":
      setupSelectionObserver(markupType: mode)
    case "text":
      setupTextGesture()
    default:
      break
    }
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

  // MARK: - Text / Sticky notes

  private func setupTextGesture() {
    guard textTapGesture == nil else { return }
    let tap = UITapGestureRecognizer(target: self, action: #selector(handleTextTap(_:)))
    tap.delegate = self
    pdfView.addGestureRecognizer(tap)
    textTapGesture = tap
  }

  private func removeTextGesture() {
    if let gesture = textTapGesture {
      pdfView.removeGestureRecognizer(gesture)
      textTapGesture = nil
    }
  }

  @objc private func handleTextTap(_ gesture: UITapGestureRecognizer) {
    let location = gesture.location(in: pdfView)
    guard let page = pdfView.page(for: location, nearest: true) else { return }

    let pdfPoint = pdfView.convert(location, to: page)

    // Show text input dialog
    guard let viewController = findViewController() else { return }
    let alert = UIAlertController(title: "Add Text", message: nil, preferredStyle: .alert)
    alert.addTextField { textField in
      textField.placeholder = "Enter text"
    }

    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    alert.addAction(UIAlertAction(title: "Add", style: .default) { [weak self] _ in
      guard let self, let text = alert.textFields?.first?.text, !text.isEmpty else { return }
      addFreeTextAnnotation(text: text, at: pdfPoint, on: page)
    })

    viewController.present(alert, animated: true)
  }

  private func addFreeTextAnnotation(text: String, at point: CGPoint, on page: PDFPage) {
    let fontSize: CGFloat = 16.0
    let font = UIFont.systemFont(ofSize: fontSize)
    let color = AnnotationSerializer.colorFromHex(annotationColor) ?? .red

    // Measure text size
    let attributes: [NSAttributedString.Key: Any] = [.font: font]
    let textSize = (text as NSString).size(withAttributes: attributes)
    let padding: CGFloat = 4.0
    let bounds = CGRect(
      x: point.x,
      y: point.y - textSize.height - padding,
      width: textSize.width + padding * 2,
      height: textSize.height + padding * 2
    )

    let annotation = PDFAnnotation(bounds: bounds, forType: .freeText, withProperties: nil)
    annotation.font = font
    annotation.fontColor = color
    annotation.color = .clear
    annotation.contents = text

    let id = UUID().uuidString
    AnnotationSerializer.tagAsModuleManaged(annotation, id: id, createdAt: Date().timeIntervalSince1970)
    page.addAnnotation(annotation)

    emitAnnotationsChanged()
  }

  private func findViewController() -> UIViewController? {
    var responder: UIResponder? = self
    while let next = responder?.next {
      if let vc = next as? UIViewController {
        return vc
      }
      responder = next
    }
    return nil
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
    onPageChanged(["page": pageIndex, "pageCount": pageCount])
  }
}
