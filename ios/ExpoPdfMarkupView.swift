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
  var currentMode: String = "none"
  var annotationColor: String = "#FF0000" {
    didSet {
      inkShapeLayer?.strokeColor = (AnnotationSerializer.colorFromHex(annotationColor) ?? .red).cgColor
    }
  }

  var annotationLineWidth: CGFloat = 2.0
  var annotationFontFamily: String?
  var useJsTextDialog: Bool = false

  var inkOverlayView: InkOverlayView?
  var disabledPdfGestures: [UIGestureRecognizer] = []
  var inkShapeLayer: CAShapeLayer?
  var inkPoints: [CGPoint] = []
  private var eraserTapGesture: UITapGestureRecognizer?
  var movePanGesture: UIPanGestureRecognizer?
  var editingOverlayLayer: CAShapeLayer?
  var textTapGesture: UITapGestureRecognizer?
  private var selectionObserver: NSObjectProtocol?
  private var selectionDebounceTimer: Timer?
  private var currentMarkupType: String?
  var movingPage: PDFPage?
  var movingOriginalModel: AnnotationModel?
  var movingPreviewModel: AnnotationModel?
  var movingPreviewAnnotation: PDFAnnotation?
  var moveStartPoint: CGPoint?

  var pendingTextPage: PDFPage?
  var pendingTextPoint: CGPoint?
  var pendingTextAnnotation: PDFAnnotation?

  var pdfScrollView: UIScrollView? {
    pdfView.subviews.first(where: { $0 is UIScrollView }) as? UIScrollView
  }

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

  func hitTestAnnotation(at point: CGPoint, on page: PDFPage) -> PDFAnnotation? {
    for annotation in page.annotations.reversed() {
      guard AnnotationSerializer.isModuleManaged(annotation) else { continue }

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
