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
}
