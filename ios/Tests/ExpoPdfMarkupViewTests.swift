@testable internal import ExpoPdfMarkup
import PDFKit
import XCTest

final class ExpoPdfMarkupViewTests: XCTestCase {
  var view: ExpoPdfMarkupView!

  override func setUp() {
    super.setUp()
    view = ExpoPdfMarkupView(appContext: nil)
  }

  override func tearDown() {
    view = nil
    super.tearDown()
  }

  @MainActor func testCommittedInkOnCroppedPageStaysUnderInputAndSerializesVisibleCoordinates() throws {
    let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 800, height: 1000))
    let document = try XCTUnwrap(PDFDocument(data: renderer.pdfData { context in context.beginPage() }))
    let page = try XCTUnwrap(document.page(at: 0))
    page.setBounds(CGRect(x: 100, y: 80, width: 600, height: 840), for: .cropBox)
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 700))
    let controller = UIViewController()
    window.rootViewController = controller
    window.makeKeyAndVisible()
    view.frame = controller.view.bounds
    controller.view.addSubview(view)
    view.pdfView.document = document
    view.layoutIfNeeded()
    view.pdfView.layoutDocumentView()
    view.setAnnotationMode("ink")
    let overlay = try XCTUnwrap(view.inkOverlayView)
    let first = view.convert(view.pdfView.convert(CGPoint(x: 180, y: 200), from: page), from: view.pdfView)
    let last = view.convert(view.pdfView.convert(CGPoint(x: 280, y: 200), from: page), from: view.pdfView)
    overlay.onBegan?(first)
    overlay.onMoved?(last)
    overlay.onEnded?()
    let result = try XCTUnwrap(AnnotationSerializer.deserialize(from: view.serializeCurrentAnnotations()))
    XCTAssertEqual(
      result.annotations.first?.decodedPaths,
      [[AnnotationPoint(x: 80, y: 120), AnnotationPoint(x: 180, y: 120)]]
    )
    window.isHidden = true
  }

  /// Shows a one-page document with a cropped page and returns a function that maps
  /// page points to view points for driving the ink overlay.
  @MainActor private func showCroppedPage() throws -> (window: UIWindow, touch: (CGFloat, CGFloat) -> CGPoint) {
    let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 800, height: 1000))
    let document = try XCTUnwrap(PDFDocument(data: renderer.pdfData { context in context.beginPage() }))
    let page = try XCTUnwrap(document.page(at: 0))
    page.setBounds(CGRect(x: 100, y: 80, width: 600, height: 840), for: .cropBox)
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 700))
    let controller = UIViewController()
    window.rootViewController = controller
    window.makeKeyAndVisible()
    view.frame = controller.view.bounds
    controller.view.addSubview(view)
    view.pdfView.document = document
    view.layoutIfNeeded()
    view.pdfView.layoutDocumentView()
    let view = view!
    return (window, { x, y in view.convert(view.pdfView.convert(CGPoint(x: x, y: y), from: page), from: view.pdfView) })
  }

  /// Draws one stroke through the ink gesture path; visible points are the page points minus the
  /// crop origin (100, 80), so it is written as (80, 120) -> (130.3, 170.7).
  @MainActor private func drawUncleanStroke(_ touch: (CGFloat, CGFloat) -> CGPoint) throws {
    view.setAnnotationMode("ink")
    let overlay = try XCTUnwrap(view.inkOverlayView)
    overlay.onBegan?(touch(180.0123, 200.0187))
    overlay.onMoved?(touch(180.0391, 199.9822)) // same as the first point once rounded
    overlay.onMoved?(touch(230.3317, 250.6871))
    overlay.onEnded?()
  }

  private func writtenInkPoints(_ json: String) throws -> [Any] {
    let written = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    let annotations = try XCTUnwrap(written["annotations"] as? [[String: Any]])
    return annotations.filter { $0["type"] as? String == "ink" }.flatMap { annotation in
      ((annotation["paths"] as? [[Any]]) ?? []).flatMap { $0 }
    }
  }

  @MainActor func testDrawnInkStrokeIsCleanedUpInAnnotationsChange() throws {
    let (window, touch) = try showCroppedPage()
    defer { window.isHidden = true }

    try drawUncleanStroke(touch)

    let json = try XCTUnwrap(view.currentAnnotationsJSON)
    XCTAssertEqual(try writtenInkPoints(json) as? [[String: Double]], [["x": 80, "y": 120], ["x": 130.3, "y": 170.7]])
    XCTAssertTrue(json.contains(#""x":80"#) && json.contains(#""y":120"#), json)
    XCTAssertTrue(json.contains(#""x":130.3"#) && json.contains(#""y":170.7"#), json)
  }

  @MainActor func testDrawnInkStrokeIsWrittenInArrayFormWithInkPointFormatArray() throws {
    let (window, touch) = try showCroppedPage()
    defer { window.isHidden = true }
    view.inkPointFormat = .array

    try drawUncleanStroke(touch)

    let json = try XCTUnwrap(view.currentAnnotationsJSON)
    XCTAssertEqual(try writtenInkPoints(json) as? [[Double]], [[80, 120], [130.3, 170.7]])
    XCTAssertTrue(json.contains("[[80,120],[130.3,170.7]]"), json)
  }

  /// Records every payload actually dispatched through `onAnnotationsChanged`.
  private func recordAnnotationsChangedEvents() -> () -> [[String: Any]] {
    var events: [[String: Any]] = []
    view.onAnnotationsChanged.onEventSent = { events.append($0) }
    return { events }
  }

  @MainActor func testChangingInkPointFormatAloneWritesNothing() throws {
    let (window, touch) = try showCroppedPage()
    defer { window.isHidden = true }
    let events = recordAnnotationsChangedEvents()

    view.inkPointFormat = .array
    view.inkPointFormat = .object
    XCTAssertEqual(events().count, 0)

    try drawUncleanStroke(touch)
    XCTAssertEqual(events().count, 1)
    let written = view.currentAnnotationsJSON

    view.inkPointFormat = .array
    XCTAssertEqual(events().count, 1)
    XCTAssertEqual(view.currentAnnotationsJSON, written)
  }

  @MainActor func testLoadingAnAnnotationSetWritesNothing() throws {
    let (window, _) = try showCroppedPage()
    defer { window.isHidden = true }
    let events = recordAnnotationsChangedEvents()
    view.inkPointFormat = .array

    for fixture in ["ink-cleanup-input", "annotations-v1-array"] {
      let url = try XCTUnwrap(Bundle(for: type(of: self)).url(forResource: fixture, withExtension: "json"))
      try view.loadAnnotations(from: String(contentsOf: url, encoding: .utf8))
    }

    XCTAssertEqual(events().count, 0)
  }

  @MainActor func testSetsLoadedInEitherFormAreWrittenInTheChosenFormOnTheNextEdit() throws {
    for (fixture, format) in [("annotations-v1", InkPointFormat.array), ("annotations-v1-array", .object)] {
      let (window, touch) = try showCroppedPage()
      defer { window.isHidden = true }
      let url = try XCTUnwrap(Bundle(for: type(of: self)).url(forResource: fixture, withExtension: "json"))
      try view.loadAnnotations(from: String(contentsOf: url, encoding: .utf8))
      view.inkPointFormat = format

      try drawUncleanStroke(touch)

      let points = try writtenInkPoints(XCTUnwrap(view.currentAnnotationsJSON))
      XCTAssertGreaterThan(points.count, 2, fixture)
      for point in points {
        XCTAssertEqual(point is [Double], format == .array, "\(fixture): \(point)")
      }
      view.removeFromSuperview()
      view = ExpoPdfMarkupView(appContext: nil)
    }
  }

  // MARK: - Initial state

  func testInitialState() {
    XCTAssertNotNil(view)
    XCTAssertTrue(view.clipsToBounds)
    XCTAssertNil(view.pdfView.document)
  }

  // MARK: - loadPdf

  func testLoadPdfWithValidFile() throws {
    let bundle = Bundle(for: type(of: self))
    guard let pdfURL = bundle.url(forResource: "test", withExtension: "pdf") else {
      XCTFail("test.pdf not found in test bundle")
      return
    }

    view.loadPdf(from: pdfURL.path)
    XCTAssertNotNil(view.pdfView.document)
    XCTAssertGreaterThan(try XCTUnwrap(view.pdfView.document?.pageCount), 0)
  }

  func testLoadPdfWithInvalidPath() {
    view.loadPdf(from: "/nonexistent/path.pdf")
    XCTAssertNil(view.pdfView.document)
  }

  func testLoadPdfSkipsDuplicateSource() {
    let bundle = Bundle(for: type(of: self))
    guard let pdfURL = bundle.url(forResource: "test", withExtension: "pdf") else {
      XCTFail("test.pdf not found in test bundle")
      return
    }

    view.loadPdf(from: pdfURL.path)
    let firstDoc = view.pdfView.document

    // Loading same source again should be a no-op (same document instance)
    view.loadPdf(from: pdfURL.path)
    XCTAssertTrue(view.pdfView.document === firstDoc)
  }

  // MARK: - goToPage

  func testGoToPageWithNoDocument() {
    // Should not crash when no document is loaded
    view.goToPage(0)
    view.goToPage(5)
    view.goToPage(-1)
  }

  func testGoToPageWithValidIndex() {
    let bundle = Bundle(for: type(of: self))
    guard let pdfURL = bundle.url(forResource: "test", withExtension: "pdf"),
          let doc = PDFDocument(url: pdfURL),
          doc.pageCount > 0
    else {
      XCTFail("test.pdf not found or empty")
      return
    }

    view.loadPdf(from: pdfURL.path)
    view.goToPage(0)

    let currentPage = view.pdfView.currentPage
    XCTAssertNotNil(currentPage)
    if let current = currentPage {
      XCTAssertEqual(view.pdfView.document?.index(for: current), 0)
    }
  }

  func testGoToPageRejectsNegativeIndex() {
    let bundle = Bundle(for: type(of: self))
    guard let pdfURL = bundle.url(forResource: "test", withExtension: "pdf") else {
      XCTFail("test.pdf not found in test bundle")
      return
    }

    view.loadPdf(from: pdfURL.path)
    let pageBefore = view.pdfView.currentPage

    view.goToPage(-1)
    // Page should not change
    XCTAssertEqual(view.pdfView.currentPage, pageBefore)
  }

  func testGoToPageRejectsOutOfBoundsIndex() throws {
    let bundle = Bundle(for: type(of: self))
    guard let pdfURL = bundle.url(forResource: "test", withExtension: "pdf") else {
      XCTFail("test.pdf not found in test bundle")
      return
    }

    view.loadPdf(from: pdfURL.path)
    let pageCount = try XCTUnwrap(view.pdfView.document?.pageCount)
    let pageBefore = view.pdfView.currentPage

    view.goToPage(pageCount + 10)
    XCTAssertEqual(view.pdfView.currentPage, pageBefore)
  }

  // MARK: - layoutSubviews

  func testLayoutSubviewsSizesPdfView() {
    view.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
    view.layoutSubviews()

    XCTAssertEqual(view.pdfView.frame, view.bounds)
  }

  // MARK: - Ink mode

  func testInkModeAddsOverlayAndDisablesPdfGestures() throws {
    view.frame = CGRect(x: 0, y: 0, width: 320, height: 480)

    // Add a known gesture so the disabled-gesture assertions are non-trivial.
    let knownGesture = UITapGestureRecognizer()
    view.pdfView.addGestureRecognizer(knownGesture)

    view.setAnnotationMode("ink")

    XCTAssertNotNil(view.inkOverlayView)
    XCTAssertTrue(try view.subviews.contains(XCTUnwrap(view.inkOverlayView)))
    XCTAssertTrue(view.disabledPdfGestures.contains(knownGesture))
    XCTAssertFalse(knownGesture.isEnabled)
    if let scrollView = view.pdfScrollView {
      XCTAssertFalse(scrollView.isScrollEnabled)
    }
  }

  func testExitingInkModeRemovesOverlayAndRestoresGestures() {
    view.frame = CGRect(x: 0, y: 0, width: 320, height: 480)

    // Add a known gesture so we can verify it is actually re-enabled on exit.
    let knownGesture = UITapGestureRecognizer()
    view.pdfView.addGestureRecognizer(knownGesture)

    view.setAnnotationMode("ink")
    XCTAssertFalse(knownGesture.isEnabled)

    view.setAnnotationMode("none")

    XCTAssertNil(view.inkOverlayView)
    XCTAssertTrue(view.disabledPdfGestures.isEmpty)
    XCTAssertTrue(knownGesture.isEnabled)
    if let scrollView = view.pdfScrollView {
      XCTAssertTrue(scrollView.isScrollEnabled)
    }
  }
}
