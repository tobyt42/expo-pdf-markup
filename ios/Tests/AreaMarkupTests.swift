@testable internal import ExpoPdfMarkup
import PDFKit
import XCTest

final class AreaMarkupTests: XCTestCase {
  @MainActor func testImageOnlyHighlightDragCreatesVisibleSerializedAreaWithoutScrolling() throws {
    let view = try makeView()
    let page = try XCTUnwrap(view.pdfView.document?.page(at: 0))
    XCTAssertTrue(page.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    view.setAnnotationMode("highlight")
    let scroll = try XCTUnwrap(view.pdfScrollView)
    let offset = scroll.contentOffset
    XCTAssertFalse(scroll.isScrollEnabled)
    let overlay = try XCTUnwrap(view.subviews.compactMap { $0 as? InkOverlayView }.first,
                                "Highlight must accept an area drag without PDFKit text selection")
    overlay.onBegan?(display(CGPoint(x: 180, y: 200), on: page, in: view))
    overlay.onMoved?(display(CGPoint(x: 280, y: 240), on: page, in: view))
    overlay.onEnded?()
    let result = try XCTUnwrap(AnnotationSerializer.deserialize(from: view.serializeCurrentAnnotations()))
    let model = try XCTUnwrap(result.annotations.first)
    XCTAssertEqual(result.annotations.count, 1)
    XCTAssertEqual(model.type, "highlight")
    XCTAssertEqual(model.bounds?.x ?? -1, 80, accuracy: 0.001)
    XCTAssertEqual(model.bounds?.y ?? -1, 120, accuracy: 0.001)
    XCTAssertEqual(model.bounds?.width ?? -1, 100, accuracy: 0.001)
    XCTAssertEqual(model.bounds?.height ?? -1, 40, accuracy: 0.001)
    XCTAssertEqual(scroll.contentOffset, offset)
    try assertRedTint(AnnotationTestFixture.thumbnail(page), x: 130, y: 140)
  }

  @MainActor func testUnderlineFollowsDisplayedBottomEdgeOnEveryRotationAndReopen() throws {
    for rotation in [0, 90, 180, 270] {
      let view = try makeView(rotation: rotation)
      let page = try XCTUnwrap(view.pdfView.document?.page(at: 0))
      view.setAnnotationMode("underline")
      let overlay = try XCTUnwrap(view.markupOverlayView)
      let coordinates = AnnotationCoordinates(page: page)
      overlay.onBegan?(display(CGPoint(x: 80, y: 120).applying(coordinates.visibleToNative), on: page, in: view))
      overlay.onMoved?(display(CGPoint(x: 180, y: 160).applying(coordinates.visibleToNative), on: page, in: view))
      overlay.onEnded?()
      let json = view.serializeCurrentAnnotations()
      let result = try XCTUnwrap(AnnotationSerializer.deserialize(from: json)?.annotations.first)
      XCTAssertEqual(result.type, "underline")
      XCTAssertEqual(result.bounds?.x ?? -1, 80, accuracy: 0.001)
      XCTAssertEqual(result.bounds?.y ?? -1, 120, accuracy: 0.001)
      XCTAssertEqual(result.bounds?.width ?? -1, 100, accuracy: 0.001)
      XCTAssertEqual(result.bounds?.height ?? -1, 40, accuracy: 0.001)
      for _ in 0 ..< 2 {
        XCTAssertNotNil(view.hitTestAnnotation(at: CGPoint(x: 130, y: 120)
            .applying(coordinates.visibleToNative), on: page), "hit the actual underline at rotation \(rotation)")
        let image = try AnnotationTestFixture.thumbnail(page)
        XCTAssertGreaterThan(try redPixelCount(image, rect: CGRect(x: 110, y: 115, width: 40, height: 15)),
                             20, "rotation \(rotation) should underline the displayed bottom edge")
        XCTAssertEqual(try redPixelCount(image, rect: CGRect(x: 110, y: 150, width: 40, height: 10)),
                       0, "rotation \(rotation) should not underline the displayed top")
        view.loadAnnotations(from: nil)
        view.loadAnnotations(from: json)
      }
    }
  }

  func testUnderlineRemainsVisibleAtRotatedCropEdge() throws {
    let document = try AnnotationTestFixture.document(rotation: 180)
    let page = try XCTUnwrap(document.page(at: 0))
    let model = AnnotationModel(id: "edge-underline", type: "underline", page: 0, color: "#FF0000",
                                bounds: AnnotationBounds(x: 80, y: 1, width: 100, height: 40))
    try page.addAnnotation(XCTUnwrap(AnnotationSerializer.toPDFAnnotation(
      model, pageBounds: page.bounds(for: .cropBox), pageRotation: page.rotation
    )))
    XCTAssertGreaterThan(try redPixelCount(AnnotationTestFixture.thumbnail(page),
                                           rect: CGRect(x: 110, y: 1, width: 40, height: 8)), 20)
  }

  @MainActor func testCancellationAndToolChangesDiscardAreaAndRestoreNavigation() throws {
    let view = try makeView()
    let page = try XCTUnwrap(view.pdfView.document?.page(at: 0))
    let scroll = try XCTUnwrap(view.pdfScrollView)
    let enabled = UITapGestureRecognizer()
    let disabled = UITapGestureRecognizer()
    disabled.isEnabled = false
    view.pdfView.addGestureRecognizer(enabled)
    view.pdfView.addGestureRecognizer(disabled)
    view.setAnnotationMode("highlight")
    let overlay = try XCTUnwrap(view.markupOverlayView)
    overlay.onBegan?(display(CGPoint(x: 180, y: 200), on: page, in: view))
    overlay.onMoved?(display(CGPoint(x: 280, y: 240), on: page, in: view))
    overlay.onCancelled?()
    overlay.onEnded?()
    XCTAssertTrue(page.annotations.isEmpty)
    XCTAssertNil(view.markupPreviewLayer?.path)
    for mode in ["underline", "ink", "text", "stamp", "move", "eraser", "none"] {
      view.setAnnotationMode("highlight")
      let active = try XCTUnwrap(view.markupOverlayView)
      active.onBegan?(display(CGPoint(x: 180, y: 200), on: page, in: view))
      active.onMoved?(display(CGPoint(x: 280, y: 240), on: page, in: view))
      view.setAnnotationMode(mode)
      active.onEnded?()
      XCTAssertTrue(page.annotations.isEmpty, "switching to \(mode) must discard the area")
      XCTAssertNil(view.markupPreviewLayer?.path)
    }
    XCTAssertNil(view.markupOverlayView)
    XCTAssertTrue(scroll.isScrollEnabled)
    XCTAssertTrue(enabled.isEnabled)
    XCTAssertFalse(disabled.isEnabled)
    scroll.isScrollEnabled = false
    view.setAnnotationMode("highlight")
    view.setAnnotationMode("none")
    XCTAssertFalse(scroll.isScrollEnabled, "restore the previous navigation state")
    scroll.isScrollEnabled = true
    view.setAnnotationMode("underline")
    let final = try XCTUnwrap(view.markupOverlayView)
    final.onBegan?(display(CGPoint(x: 180, y: 200), on: page, in: view))
    final.onMoved?(display(CGPoint(x: 280, y: 240), on: page, in: view))
    final.onEnded?()
    XCTAssertEqual(page.annotations.count, 1, "a subsequent drag must still work")
  }

  @MainActor func testAreaMarkupOnTextAndScanControlsSurvivesZoomMoveAndReopen() throws {
    for crop in [CGRect(x: 0, y: 0, width: 800, height: 1000),
                 CGRect(x: 0, y: 0, width: 600, height: 840), AnnotationTestFixture.crop] {
      for text in [false, true] {
        for mode in ["highlight", "underline"] {
          let view = try makeView(crop: crop, text: text)
          let page = try XCTUnwrap(view.pdfView.document?.page(at: 0))
          XCTAssertEqual(!(page.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true), text)
          view.pdfView.scaleFactor *= 1.5
          view.pdfScrollView?.contentOffset = CGPoint(x: 20, y: 40)
          view.setAnnotationMode(mode)
          let overlay = try XCTUnwrap(view.markupOverlayView)
          overlay.onBegan?(display(CGPoint(x: crop.minX + 80, y: crop.minY + 400), on: page, in: view))
          overlay.onMoved?(display(CGPoint(x: crop.minX + 180, y: crop.minY + 440), on: page, in: view))
          overlay.onEnded?()
          let data = AnnotationSerializer.deserialize(from: view.serializeCurrentAnnotations())
          let model = try XCTUnwrap(data?.annotations.first)
          XCTAssertEqual(model.bounds?.x ?? -1, 80, accuracy: 0.001)
          XCTAssertEqual(model.bounds?.y ?? -1, 400, accuracy: 0.001)
          XCTAssertEqual(model.bounds?.width ?? -1, 100, accuracy: 0.001)
          XCTAssertEqual(model.bounds?.height ?? -1, 40, accuracy: 0.001)
          let target = CGPoint(x: crop.minX + 130, y: crop.minY + (mode == "highlight" ? 420 : 400))
          XCTAssertNotNil(view.hitTestAnnotation(at: target, on: page))
          view.setAnnotationMode("move")
          let pan = AreaMarkupPan()
          pan.suppliedLocation = view.pdfView.convert(target, from: page)
          pan.suppliedState = .began
          view.handleMovePan(pan)
          pan.suppliedLocation = view.pdfView.convert(CGPoint(x: target.x + 20, y: target.y + 30), from: page)
          pan.suppliedState = .changed
          view.handleMovePan(pan)
          pan.suppliedState = .ended
          view.handleMovePan(pan)
          let json = view.serializeCurrentAnnotations()
          let moved = try XCTUnwrap(AnnotationSerializer.deserialize(from: json)?.annotations.first)
          XCTAssertEqual(moved.id, model.id)
          XCTAssertEqual(moved.bounds?.x ?? -1, 100, accuracy: 0.001)
          XCTAssertEqual(moved.bounds?.y ?? -1, 430, accuracy: 0.001)
          XCTAssertEqual(moved.color, model.color)
          XCTAssertEqual(moved.alpha, model.alpha)
          XCTAssertNotNil(view.editingOverlayLayer?.path)
          let reopened = try makeView(crop: crop, text: text)
          reopened.loadAnnotations(from: json)
          let reopenedData = AnnotationSerializer.deserialize(from: reopened.serializeCurrentAnnotations())
          XCTAssertEqual(reopenedData?.annotations, [moved])
          let reopenedPage = try XCTUnwrap(reopened.pdfView.document?.page(at: 0))
          let image = try AnnotationTestFixture.thumbnail(reopenedPage)
          let paintedY = mode == "highlight" ? 450 : 430
          let visibleLine = CGRect(x: 130, y: paintedY - 1, width: 40, height: 3)
          XCTAssertGreaterThan(try redPixelCount(image, rect: visibleLine), 20)
          let reopenedTarget = CGPoint(x: crop.minX + 150, y: crop.minY + CGFloat(paintedY))
          XCTAssertNotNil(reopened.hitTestAnnotation(at: reopenedTarget, on: reopenedPage))
        }
      }
    }
  }

  @MainActor func testPageKeysSourceChangesAndNoneModeDiscardStaleDrags() throws {
    let view = try makeView()
    let document = try XCTUnwrap(view.pdfView.document)
    let first = try XCTUnwrap(document.page(at: 0))
    let second = try XCTUnwrap(first.copy() as? PDFPage)
    document.insert(second, at: 1)
    view.setDisplayMode("book")
    view.goToPage(0)
    view.setAnnotationMode("highlight")
    let overlay = try XCTUnwrap(view.markupOverlayView)
    func begin() {
      overlay.onBegan?(display(CGPoint(x: 180, y: 200), on: first, in: view))
      overlay.onMoved?(display(CGPoint(x: 280, y: 240), on: first, in: view))
    }
    begin()
    view.handleBookTap(at: CGPoint(x: view.bounds.maxX - 1, y: view.bounds.midY))
    XCTAssertTrue(view.pdfView.currentPage === first, "area tools block touch page turns")
    let command = try XCTUnwrap(view.keyCommands?.first { $0.input == UIKeyCommand.inputRightArrow })
    try view.perform(XCTUnwrap(command.action), with: command)
    XCTAssertTrue(view.pdfView.currentPage === second, "hardware navigation remains available")
    overlay.onEnded?()
    XCTAssertTrue(first.annotations.isEmpty)
    XCTAssertTrue(second.annotations.isEmpty)
    XCTAssertNil(view.markupPreviewLayer?.path)
    view.goToPage(0)
    begin()
    view.goToPage(1)
    overlay.onEnded?()
    XCTAssertTrue(first.annotations.isEmpty, "page prop navigation cancels the held drag")
    view.goToPage(0)
    begin()
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("area-source-\(UUID().uuidString).pdf")
    defer { try? FileManager.default.removeItem(at: url) }
    XCTAssertTrue(try AnnotationTestFixture.document(text: true).write(to: url))
    view.loadPdf(from: url.path)
    overlay.onEnded?()
    XCTAssertTrue(try XCTUnwrap(view.pdfView.document?.page(at: 0)).annotations.isEmpty)
    XCTAssertNil(view.markupPreviewLayer?.path)
    XCTAssertFalse(try XCTUnwrap(view.pdfScrollView).isScrollEnabled)
    view.pdfView.document = document
    view.goToPage(0)
    view.setAnnotationMode("none")
    XCTAssertTrue(try XCTUnwrap(view.pdfScrollView).isScrollEnabled)
    view.handleBookTap(at: CGPoint(x: view.bounds.maxX - 1, y: view.bounds.midY))
    XCTAssertTrue(view.pdfView.currentPage === second, "touch page turning resumes after leaving the tool")
  }

  private func redPixelCount(_ image: CGImage, rect: CGRect) throws -> Int {
    let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let pixels = try XCTUnwrap(context.data).bindMemory(to: UInt8.self, capacity: image.width * image.height * 4)
    var count = 0
    for y in Int(rect.minY) ..< Int(rect.maxY) {
      for x in Int(rect.minX) ..< Int(rect.maxX) {
        let index = ((image.height - 1 - y) * image.width + x) * 4
        if pixels[index] > 200, pixels[index + 1] < 220, pixels[index + 2] < 220 { count += 1 }
      }
    }
    return count
  }

  @MainActor private func makeView(crop: CGRect = AnnotationTestFixture.crop,
                                   rotation: Int = 0, text: Bool = false) throws -> ExpoPdfMarkupView {
    let view = ExpoPdfMarkupView(appContext: nil)
    view.frame = UIScreen.main.bounds
    view.pdfView.document = try AnnotationTestFixture.document(crop: crop, rotation: rotation, text: text)
    view.layoutIfNeeded()
    view.pdfView.layoutDocumentView()
    return view
  }

  @MainActor private func display(_ point: CGPoint, on page: PDFPage, in view: ExpoPdfMarkupView) -> CGPoint {
    view.convert(view.pdfView.convert(point, from: page), from: view.pdfView)
  }

  private func assertRedTint(_ image: CGImage, x: Int, y: Int,
                             file: StaticString = #filePath, line: UInt = #line) throws {
    let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let pixels = try XCTUnwrap(context.data).bindMemory(to: UInt8.self, capacity: image.width * image.height * 4)
    let index = ((image.height - 1 - y) * image.width + x) * 4
    XCTAssertGreaterThan(pixels[index], 200, file: file, line: line)
    XCTAssertLessThan(pixels[index + 1], 220, file: file, line: line)
    XCTAssertLessThan(pixels[index + 2], 220, file: file, line: line)
  }
}

private final class AreaMarkupPan: UIPanGestureRecognizer {
  var suppliedLocation: CGPoint = .zero
  var suppliedState: UIGestureRecognizer.State = .possible
  override var state: UIGestureRecognizer.State {
    get { suppliedState }
    set { suppliedState = newValue }
  }

  override func location(in _: UIView?) -> CGPoint {
    suppliedLocation
  }
}
