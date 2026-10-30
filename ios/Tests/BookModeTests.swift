@testable internal import ExpoPdfMarkup
import PDFKit
import XCTest

final class BookModeTests: XCTestCase {
  var view: ExpoPdfMarkupView!
  var reportedPages: [Int] = []

  override func setUp() {
    super.setUp()
    view = ExpoPdfMarkupView(appContext: nil)
    view.frame = CGRect(x: 0, y: 0, width: 400, height: 600)
    view.layoutIfNeeded()
    reportedPages = []
    view.onPageChanged.onEventSent = { [weak self] payload in
      if let page = payload["page"] as? Int {
        self?.reportedPages.append(page)
      }
    }
  }

  override func tearDown() {
    view = nil
    super.tearDown()
  }

  private func fixturePath(_ name: String) throws -> String {
    let url = Bundle(for: type(of: self)).url(forResource: name, withExtension: "pdf")
    return try XCTUnwrap(url, "\(name).pdf missing from test bundle").path
  }

  private func loadBook(_ name: String = "book-sample", startPage: Int = 0) throws {
    view.setDisplayMode("book")
    try view.loadPdf(from: fixturePath(name))
    view.layoutIfNeeded()
    view.goToPage(startPage)
    reportedPages = []
  }

  private var shownPage: Int? {
    guard let document = view.pdfView.document, let page = view.pdfView.currentPage else { return nil }
    return document.index(for: page)
  }

  // MARK: - Presentation

  func testBookModeShowsOnePageAtATime() throws {
    try loadBook()
    XCTAssertEqual(view.pdfView.displayMode, .singlePage)
    XCTAssertTrue(view.pdfView.autoScales)
  }

  func testSwitchingModesKeepsTheCurrentPage() throws {
    try view.loadPdf(from: fixturePath("book-sample"))
    view.layoutIfNeeded()
    view.goToPage(3)
    reportedPages = []

    view.setDisplayMode("book")
    XCTAssertEqual(shownPage, 3)
    XCTAssertEqual(reportedPages, [], "switching mode is not a turn")

    view.setDisplayMode("continuous")
    XCTAssertEqual(shownPage, 3)
    XCTAssertEqual(view.pdfView.displayMode, .singlePageContinuous)
  }

  func testContinuousModeIsLeftAsItWas() throws {
    let gesturesBefore = view.pdfView.gestureRecognizers?.count ?? 0
    view.setDisplayMode("book")
    view.setDisplayMode("continuous")
    try view.loadPdf(from: fixturePath("book-sample"))

    XCTAssertEqual(view.pdfView.displayMode, .singlePageContinuous)
    XCTAssertEqual(view.pdfView.displayDirection, .vertical)
    XCTAssertEqual(view.pdfView.pageBreakMargins, UIEdgeInsets(top: 0, left: 0, bottom: 8, right: 0))
    XCTAssertEqual(view.pdfView.gestureRecognizers?.count ?? 0, gesturesBefore)
  }

  func testRotatingOrResizingKeepsTheCurrentPage() throws {
    try loadBook(startPage: 3)
    view.frame = CGRect(x: 0, y: 0, width: 600, height: 400)
    view.layoutIfNeeded()
    XCTAssertEqual(shownPage, 3)
    XCTAssertEqual(view.pdfView.frame, view.bounds)
    XCTAssertEqual(reportedPages, [])
  }

  func testDisplayModeSetBeforeTheSourceStillAppliesBookMode() throws {
    try loadBook()
    XCTAssertEqual(shownPage, 0)
    XCTAssertEqual(view.pdfView.displayMode, .singlePage)
  }

  // MARK: - Edge taps

  func testTappingTheRightEdgeTurnsToTheNextPage() throws {
    try loadBook(startPage: 2)
    view.handleBookTap(at: CGPoint(x: 395, y: 300))
    XCTAssertEqual(shownPage, 3)
    XCTAssertEqual(reportedPages, [3])
  }

  func testTappingTheLeftEdgeTurnsToThePreviousPage() throws {
    try loadBook(startPage: 2)
    view.handleBookTap(at: CGPoint(x: 5, y: 300))
    XCTAssertEqual(shownPage, 1)
    XCTAssertEqual(reportedPages, [1])
  }

  func testEdgeZonesAreTheOuterQuarter() throws {
    try loadBook(startPage: 2)
    view.handleBookTap(at: CGPoint(x: 101, y: 300))
    view.handleBookTap(at: CGPoint(x: 200, y: 300))
    view.handleBookTap(at: CGPoint(x: 299, y: 300))
    XCTAssertEqual(shownPage, 2, "a tap in the middle does nothing")
    XCTAssertEqual(reportedPages, [])

    view.handleBookTap(at: CGPoint(x: 99, y: 300))
    XCTAssertEqual(shownPage, 1)
  }

  func testEdgeZonesAreAtLeast44PointsWide() throws {
    view.frame = CGRect(x: 0, y: 0, width: 120, height: 400)
    view.layoutIfNeeded()
    try loadBook(startPage: 2)

    view.handleBookTap(at: CGPoint(x: 42, y: 200))
    XCTAssertEqual(shownPage, 1)
    view.handleBookTap(at: CGPoint(x: 78, y: 200))
    XCTAssertEqual(shownPage, 2)
    view.handleBookTap(at: CGPoint(x: 60, y: 200))
    XCTAssertEqual(shownPage, 2)
  }

  func testEdgeTapsDoNothingInContinuousMode() throws {
    try view.loadPdf(from: fixturePath("book-sample"))
    view.layoutIfNeeded()
    view.goToPage(2)
    reportedPages = []

    view.handleBookTap(at: CGPoint(x: 395, y: 300))
    XCTAssertEqual(shownPage, 2)
    XCTAssertEqual(reportedPages, [])
  }

  // MARK: - Swipes

  func testSwipingLeftTurnsToTheNextPage() throws {
    try loadBook(startPage: 2)
    view.endBookSwipe(translationX: -150, velocityX: -300)
    XCTAssertEqual(shownPage, 3)
    XCTAssertEqual(reportedPages, [3])
  }

  func testSwipingRightTurnsToThePreviousPage() throws {
    try loadBook(startPage: 2)
    view.endBookSwipe(translationX: 150, velocityX: 300)
    XCTAssertEqual(shownPage, 1)
    XCTAssertEqual(reportedPages, [1])
  }

  func testAFastFlickTurnsEvenOverAShortDistance() throws {
    try loadBook(startPage: 2)
    view.endBookSwipe(translationX: -30, velocityX: -900)
    XCTAssertEqual(shownPage, 3)
  }

  func testAShortSlowDragSpringsBackWithoutTurning() throws {
    try loadBook(startPage: 2)
    view.endBookSwipe(translationX: -30, velocityX: -50)
    XCTAssertEqual(shownPage, 2)
    XCTAssertEqual(reportedPages, [])
  }

  func testSwipeLeftMeansNextInARightToLeftLayout() throws {
    view.semanticContentAttribute = .forceRightToLeft
    view.pdfView.semanticContentAttribute = .forceRightToLeft
    try loadBook(startPage: 2)
    view.endBookSwipe(translationX: -150, velocityX: -300)
    XCTAssertEqual(shownPage, 3)
  }

  func testSwipesDoNotTurnWithAMarkupToolActive() throws {
    try loadBook(startPage: 2)
    view.setAnnotationMode("ink")
    view.endBookSwipe(translationX: -150, velocityX: -300)
    XCTAssertEqual(shownPage, 2)
    XCTAssertEqual(reportedPages, [])
  }

  func testSwipesDoNotTurnWhileZoomedIn() throws {
    try loadBook(startPage: 2)
    view.pdfView.scaleFactor = view.pdfView.scaleFactorForSizeToFit * 2
    view.endBookSwipe(translationX: -150, velocityX: -300)
    XCTAssertEqual(shownPage, 2)
    XCTAssertEqual(reportedPages, [])
  }

  func testSwipingPastTheLastPageBounces() throws {
    try loadBook(startPage: 5)
    view.endBookSwipe(translationX: -150, velocityX: -300)
    XCTAssertEqual(shownPage, 5)
    XCTAssertEqual(reportedPages, [])
  }

  // MARK: - Animation on screen

  private func hostInWindow() -> UIWindow {
    let window = UIWindow(frame: view.frame)
    window.addSubview(view)
    window.isHidden = false
    view.layoutIfNeeded()
    return window
  }

  private func waitForAnimations() {
    let settled = expectation(description: "animations settle")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { settled.fulfill() }
    wait(for: [settled], timeout: 2)
  }

  func testAnimatedTurnSlidesAndSettlesOnTheNewPage() throws {
    let window = hostInWindow()
    try loadBook(startPage: 2)
    let subviewsBefore = view.subviews.count

    view.handleBookTap(at: CGPoint(x: 395, y: 300))
    XCTAssertEqual(shownPage, 3)
    XCTAssertNotNil(view.pdfView.layer.animationKeys(), "the new page slides in")
    XCTAssertEqual(view.subviews.count, subviewsBefore + 1, "the outgoing page slides out")

    waitForAnimations()
    XCTAssertEqual(view.pdfView.transform, .identity)
    XCTAssertEqual(view.subviews.count, subviewsBefore, "the outgoing snapshot is removed")
    XCTAssertEqual(reportedPages, [3])
    window.isHidden = true
  }

  func testAnimatedBounceReturnsToRest() throws {
    let window = hostInWindow()
    try loadBook(startPage: 5)
    view.handleBookTap(at: CGPoint(x: 395, y: 300))
    waitForAnimations()
    XCTAssertEqual(view.pdfView.transform, .identity)
    XCTAssertEqual(shownPage, 5)
    window.isHidden = true
  }

  // MARK: - Ends of the document

  func testTurningBeforeTheFirstPageBouncesBack() throws {
    try loadBook(startPage: 0)
    view.handleBookTap(at: CGPoint(x: 5, y: 300))
    XCTAssertEqual(shownPage, 0)
    XCTAssertEqual(reportedPages, [])
  }

  func testTurningPastTheLastPageBouncesAndDoesNotWrap() throws {
    try loadBook(startPage: 5)
    view.handleBookTap(at: CGPoint(x: 395, y: 300))
    XCTAssertEqual(shownPage, 5)
    XCTAssertEqual(reportedPages, [])
  }

  func testAOnePageDocumentNeverTurns() throws {
    try loadBook("single-page")
    view.handleBookTap(at: CGPoint(x: 395, y: 300))
    view.handleBookTap(at: CGPoint(x: 5, y: 300))
    XCTAssertEqual(shownPage, 0)
    XCTAssertEqual(reportedPages, [])
  }

  // MARK: - page prop and onPageChanged

  func testPagePropJumpsInBookMode() throws {
    try loadBook(startPage: 0)
    view.goToPage(4)
    XCTAssertEqual(shownPage, 4)
    XCTAssertEqual(reportedPages, [4])
  }

  func testOnPageChangedFiresOncePerTurn() throws {
    try loadBook(startPage: 0)
    view.handleBookTap(at: CGPoint(x: 395, y: 300))
    view.handleBookTap(at: CGPoint(x: 395, y: 300))
    view.handleBookTap(at: CGPoint(x: 5, y: 300))
    XCTAssertEqual(reportedPages, [1, 2, 1])
  }

  // MARK: - Turn policy

  func testEdgeTapsDoNotTurnWithAnyMarkupToolActive() throws {
    try loadBook(startPage: 2)
    for mode in ["ink", "highlight", "underline", "text", "stamp", "move", "eraser"] {
      view.setAnnotationMode(mode)
      view.handleBookTap(at: CGPoint(x: 395, y: 300))
      view.handleBookTap(at: CGPoint(x: 5, y: 300))
      XCTAssertEqual(shownPage, 2, "\(mode) must block edge taps")
    }
    XCTAssertEqual(reportedPages, [])

    view.setAnnotationMode("none")
    view.handleBookTap(at: CGPoint(x: 395, y: 300))
    XCTAssertEqual(shownPage, 3)
  }

  func testInkLandsOnThePageShownInBookMode() throws {
    try loadBook(startPage: 3)
    view.setAnnotationMode("ink")
    let overlay = try XCTUnwrap(view.inkOverlayView)
    overlay.onBegan?(CGPoint(x: 150, y: 250))
    overlay.onMoved?(CGPoint(x: 200, y: 300))
    overlay.onMoved?(CGPoint(x: 250, y: 350))
    overlay.onEnded?()

    XCTAssertEqual(shownPage, 3)
    let data = try XCTUnwrap(AnnotationSerializer.deserialize(from: view.serializeCurrentAnnotations()))
    XCTAssertEqual(data.annotations.map(\.page), [3])
  }

  func testEdgeTapsDoNotTurnWhileZoomedIn() throws {
    try loadBook(startPage: 2)
    view.pdfView.scaleFactor = view.pdfView.scaleFactorForSizeToFit * 2
    view.handleBookTap(at: CGPoint(x: 395, y: 300))
    XCTAssertEqual(shownPage, 2)
    XCTAssertEqual(reportedPages, [])
  }

  func testTurningResetsTheNewPageToFit() throws {
    try loadBook(startPage: 2)
    view.pdfView.scaleFactor = view.pdfView.scaleFactorForSizeToFit * 2
    XCTAssertTrue(view.turnBookPage(.next, from: .key))
    XCTAssertEqual(shownPage, 3)
    XCTAssertEqual(view.pdfView.scaleFactor, view.pdfView.scaleFactorForSizeToFit, accuracy: 0.001)
  }
}
