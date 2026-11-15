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
