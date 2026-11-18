@testable internal import ExpoPdfMarkup
import PDFKit
import XCTest

final class RotatedAnnotationRenderingTests: XCTestCase {
  var retainedDocuments: [PDFDocument] = []
  @MainActor func testLiveTextCreationEditingAndFreshReloadPreserveHorizontalVisibleGeometry() throws {
    for rotation in [0, 90, 180, 270] {
      let document = try AnnotationTestFixture.document(rotation: rotation)
      retainedDocuments.append(document)
      let page = try XCTUnwrap(document.page(at: 0))
      let window = try testWindow()
      let host = UIView(frame: window.bounds)
      window.addSubview(host)
      let view = ExpoPdfMarkupView(appContext: nil)
      // These tests drive module input and custom appearances; keep PDFKit's
      // built-in text-selection gestures out of this rendering harness.
      if #available(iOS 16.0, *) { view.pdfView.isInMarkupMode = true }
      defer {
        view.pdfView.document = nil
        view.removeFromSuperview()
        host.removeFromSuperview()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        retainedDocuments.removeAll()
      }
      view.frame = host.bounds
      host.addSubview(view)
      view.pdfView.document = document
      view.layoutIfNeeded()
      view.pdfView.layoutDocumentView()
      view.useJsTextDialog = true
      view.annotationColor = "#FF0000"
      view.annotationFontFamily = "Helvetica"
      view.setAnnotationMode("text")
      let tap = RenderingTestTap()
      let coordinates = AnnotationCoordinates(page: page)
      tap.point = view.pdfView.convert(CGPoint(x: 80, y: 320).applying(coordinates.visibleToNative), from: page)
      view.handleTextTap(tap)
      view.provideTextInput(text: "MMMMMMMMMM")
      let created = try model(view)
      XCTAssertEqual(created.color, "#FF0000")
      XCTAssertEqual(created.type, "freeText")
      let initialBounds = try XCTUnwrap(created.bounds?.cgRect)
      XCTAssertGreaterThan(initialBounds.width, initialBounds.height * 3, "rotation \(rotation)")
      XCTAssertEqual(initialBounds.minX, 80, accuracy: 0.001)
      try assertHorizontalText(page, near: CGRect(x: 80, y: 290, width: 200, height: 50))
      try assertLiveHorizontalText(view, on: page, within: CGRect(x: 80, y: 290, width: 200, height: 50))
      let createdJSON = view.serializeCurrentAnnotations()
      view.loadAnnotations(from: nil)
      view.loadAnnotations(from: createdJSON)
      XCTAssertEqual(try model(view), created, "created text shifted on reload at rotation \(rotation)")

      let annotation = try XCTUnwrap(page.annotations.first)
      tap.point = view.pdfView.convert(CGPoint(x: annotation.bounds.midX, y: annotation.bounds.midY), from: page)
      view.handleTextTap(tap)
      view.provideTextInput(text: "MMMMMMMMMMMMMMMM")
      let edited = try model(view)
      XCTAssertEqual(edited.id, created.id)
      XCTAssertEqual(edited.createdAt, created.createdAt)
      XCTAssertEqual(edited.color, created.color)
      XCTAssertEqual(edited.fontFamily, created.fontFamily)
      XCTAssertEqual(edited.fontSize, created.fontSize)
      XCTAssertEqual(edited.contents, "MMMMMMMMMMMMMMMM")
      XCTAssertEqual(edited.bounds?.cgRect.minX, created.bounds?.cgRect.minX)
      XCTAssertEqual(edited.bounds?.cgRect.maxY, created.bounds?.cgRect.maxY)
      let editedJSON = view.serializeCurrentAnnotations()
      let reopened = try AnnotationTestFixture.document(rotation: rotation)
      retainedDocuments.append(reopened)
      view.pdfView.document = reopened
      view.loadAnnotations(from: nil)
      view.loadAnnotations(from: editedJSON)
      XCTAssertEqual(try model(view), edited, "edited text shifted on fresh reopen at rotation \(rotation)")
      try assertHorizontalText(XCTUnwrap(reopened.page(at: 0)), near: CGRect(x: 80, y: 290, width: 300, height: 50))
      view.layoutIfNeeded()
      try assertLiveHorizontalText(view, on: XCTUnwrap(reopened.page(at: 0)),
                                   within: CGRect(x: 80, y: 290, width: 300, height: 50))
      let attachment = try XCTAttachment(image: UIImage(cgImage: snapshot(view)))
      attachment.name = "Live text rotation \(rotation) after fresh reopen"
      attachment.lifetime = .keepAlways
      add(attachment)
    }
  }

  @MainActor func testLiveAndThumbnailStampGlyphsStayAtVisibleBoundsForEveryRotation() throws {
    for rotation in [0, 90, 180, 270] {
      let document = try AnnotationTestFixture.document(rotation: rotation)
      retainedDocuments.append(document)
      let page = try XCTUnwrap(document.page(at: 0))
      let coordinates = AnnotationCoordinates(page: page)
      let window = try testWindow()
      let host = UIView(frame: window.bounds)
      window.addSubview(host)
      let view = ExpoPdfMarkupView(appContext: nil)
      // These tests drive module input and custom appearances; keep PDFKit's
      // built-in text-selection gestures out of this rendering harness.
      if #available(iOS 16.0, *) { view.pdfView.isInMarkupMode = true }
      defer {
        view.pdfView.document = nil
        view.removeFromSuperview()
        host.removeFromSuperview()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        retainedDocuments.removeAll()
      }
      view.frame = host.bounds
      host.addSubview(view)
      view.pdfView.document = document
      view.layoutIfNeeded()
      view.pdfView.layoutDocumentView()
      view.annotationColor = "#FF0000"
      view.setAnnotationMode("stamp")
      let beforeThumbnail = try AnnotationTestFixture.thumbnail(page)
      let scaledSize = CGSize(width: coordinates.visibleBounds.width / 2, height: coordinates.visibleBounds.height / 2)
      let beforeScaled = try XCTUnwrap(page.thumbnail(of: scaledSize, for: .cropBox).cgImage)
      let beforeLive = try snapshot(view)
      let positions = [20, 270, 530]
      for (index, glyph) in ["♫", "★", "🎵"].enumerated() {
        view.stampText = glyph
        let tap = RenderingTestTap()
        tap.point = view.pdfView.convert(
          CGPoint(x: positions[index] + 24, y: 84).applying(coordinates.visibleToNative), from: page
        )
        view.handleStampTap(tap)
      }
      let original = view.serializeCurrentAnnotations()
      for pass in 0 ..< 2 {
        let afterThumbnail = try AnnotationTestFixture.thumbnail(page)
        let afterScaled = try XCTUnwrap(page.thumbnail(of: scaledSize, for: .cropBox).cgImage)
        let afterLive = try snapshot(view)
        for (index, x) in positions.enumerated() {
          let visible = CGRect(x: x, y: 60, width: 48, height: 48)
          let thumbnailRegion = CGRect(x: x, y: afterThumbnail.height - 108, width: 48, height: 48)
          XCTAssertGreaterThan(try changedPixels(beforeThumbnail, afterThumbnail, within: thumbnailRegion), 30,
                               "thumbnail glyph \(index), rotation \(rotation), pass \(pass)")
          let scale = CGFloat(afterScaled.width) / coordinates.visibleBounds.width
          let scaledRegion = CGRect(x: visible.minX * scale,
                                    y: CGFloat(afterScaled.height) - visible.maxY * scale,
                                    width: visible.width * scale, height: visible.height * scale)
          XCTAssertGreaterThan(try changedPixels(beforeScaled, afterScaled, within: scaledRegion), 8,
                               "scaled thumbnail glyph \(index), rotation \(rotation), pass \(pass)")
          let native = visible.applying(coordinates.visibleToNative)
          let liveRegion = view.convert(view.pdfView.convert(native, from: page), from: view.pdfView)
          XCTAssertGreaterThan(try changedPixels(beforeLive, afterLive, within: liveRegion), 8,
                               "live glyph \(index), rotation \(rotation), pass \(pass)")
        }
        let attachment = XCTAttachment(image: UIImage(cgImage: afterLive))
        attachment.name = "Stamp glyphs rotation \(rotation) pass \(pass)"
        attachment.lifetime = .keepAlways
        add(attachment)
        view.loadAnnotations(from: nil)
        view.loadAnnotations(from: original)
        let reloaded = try XCTUnwrap(AnnotationSerializer.deserialize(from: view.serializeCurrentAnnotations()))
        XCTAssertEqual(reloaded, AnnotationSerializer.deserialize(from: original))
      }
    }
  }

  @MainActor func testUnderlineDrawsTheVisibleLowerEdgeInLiveViewAndThumbnailAtEveryRotation() throws {
    for rotation in [0, 90, 180, 270] {
      let document = try AnnotationTestFixture.document(rotation: rotation)
      retainedDocuments.append(document)
      let page = try XCTUnwrap(document.page(at: 0))
      let coordinates = AnnotationCoordinates(page: page)
      let window = try testWindow()
      let host = UIView(frame: window.bounds)
      window.addSubview(host)
      let view = ExpoPdfMarkupView(appContext: nil)
      // These tests drive module input and custom appearances; keep PDFKit's
      // built-in text-selection gestures out of this rendering harness.
      if #available(iOS 16.0, *) { view.pdfView.isInMarkupMode = true }
      defer {
        view.pdfView.document = nil
        view.removeFromSuperview()
        host.removeFromSuperview()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        retainedDocuments.removeAll()
      }
      view.frame = host.bounds
      host.addSubview(view)
      view.pdfView.document = document
      view.layoutIfNeeded()
      view.pdfView.layoutDocumentView()
      let beforeThumbnail = try AnnotationTestFixture.thumbnail(page)
      let scaledSize = CGSize(width: coordinates.visibleBounds.width / 2, height: coordinates.visibleBounds.height / 2)
      let beforeScaled = try XCTUnwrap(page.thumbnail(of: scaledSize, for: .cropBox).cgImage)
      let beforeLive = try snapshot(view)
      let model = AnnotationModel(id: "underline", type: "underline", page: 0, color: "#FF0000",
                                  bounds: AnnotationBounds(x: 80, y: 300, width: 160, height: 24), createdAt: 123)
      try page.addAnnotation(XCTUnwrap(AnnotationSerializer.toPDFAnnotation(model,
                                                                            pageBounds: page.bounds(for: .cropBox),
                                                                            pageRotation: rotation)))
      let afterThumbnail = try AnnotationTestFixture.thumbnail(page)
      let afterScaled = try XCTUnwrap(page.thumbnail(of: scaledSize, for: .cropBox).cgImage)
      let scale = CGFloat(afterScaled.width) / coordinates.visibleBounds.width
      let scaledEdge = CGRect(x: 80 * scale, y: CGFloat(afterScaled.height) - 303 * scale,
                              width: 160 * scale, height: 6 * scale)
      XCTAssertGreaterThan(try changedPixels(beforeScaled, afterScaled, within: scaledEdge), 30)
      let afterLive = try snapshot(view)
      let edge = CGRect(x: 80, y: 297, width: 160, height: 6)
      let thumbnailEdge = CGRect(x: 80, y: afterThumbnail.height - 303, width: 160, height: 6)
      XCTAssertGreaterThan(try changedPixels(beforeThumbnail, afterThumbnail, within: thumbnailEdge), 100,
                           "thumbnail lower edge, rotation \(rotation)")
      let liveEdge = view.convert(
        view.pdfView.convert(edge.applying(coordinates.visibleToNative), from: page),
        from: view.pdfView
      )
      XCTAssertGreaterThan(try changedPixels(beforeLive, afterLive, within: liveEdge), 30,
                           "live lower edge, rotation \(rotation)")
      XCTAssertEqual(AnnotationSerializer.toModel(from: page.annotations[0], page: 0), model)
      let saved = view.serializeCurrentAnnotations()
      view.loadAnnotations(from: nil)
      view.loadAnnotations(from: saved)
      XCTAssertEqual(try self.model(view), model)
      view.setAnnotationMode("move")
      let pan = RenderingTestPan()
      pan.point = view.pdfView.convert(CGPoint(x: 160, y: 310).applying(coordinates.visibleToNative), from: page)
      pan.suppliedState = .began
      view.handleMovePan(pan)
      pan.point = view.pdfView.convert(CGPoint(x: 180, y: 340).applying(coordinates.visibleToNative), from: page)
      pan.suppliedState = .changed
      view.handleMovePan(pan)
      pan.suppliedState = .ended
      view.handleMovePan(pan)
      view.setAnnotationMode("none")
      let moved = try self.model(view)
      XCTAssertEqual(moved.type, "underline")
      XCTAssertEqual(moved.id, model.id)
      XCTAssertEqual(moved.createdAt, model.createdAt)
      XCTAssertEqual(moved.color, model.color)
      XCTAssertEqual(try XCTUnwrap(moved.bounds?.x), 100, accuracy: 0.001)
      XCTAssertEqual(try XCTUnwrap(moved.bounds?.y), 330, accuracy: 0.001)
      XCTAssertNotNil(view.hitTestAnnotation(
        at: CGPoint(x: 180, y: 330).applying(coordinates.visibleToNative),
        on: page
      ))
      let movedThumbnail = try AnnotationTestFixture.thumbnail(page)
      XCTAssertGreaterThan(try changedPixels(
        beforeThumbnail,
        movedThumbnail,
        within: CGRect(x: 100, y: movedThumbnail.height - 333, width: 160, height: 6)
      ), 100)
      let movedLive = try snapshot(view)
      let movedEdge = CGRect(x: 100, y: 327, width: 160, height: 6)
      let movedLiveEdge = view.convert(
        view.pdfView.convert(movedEdge.applying(coordinates.visibleToNative), from: page),
        from: view.pdfView
      )
      XCTAssertGreaterThan(try changedPixels(beforeLive, movedLive, within: movedLiveEdge), 30)
    }
  }

  func testFullPageCustomAnnotationsKeepOrientationInScaledThumbnails() throws {
    for type in ["underline", "stamp"] {
      let document = try AnnotationTestFixture.document(rotation: 180)
      let page = try XCTUnwrap(document.page(at: 0))
      let sizes = [CGSize(width: 600, height: 840), CGSize(width: 300, height: 420)]
      let baselines = try sizes.map { try XCTUnwrap(page.thumbnail(of: $0, for: .cropBox).cgImage) }
      let model = AnnotationModel(id: type, type: type, page: 0, color: "#FF0000",
                                  bounds: AnnotationBounds(x: 0, y: 0, width: 600, height: 840), createdAt: 123,
                                  text: type == "stamp" ? "L" : nil)
      try page.addAnnotation(XCTUnwrap(AnnotationSerializer.toPDFAnnotation(model,
                                                                            pageBounds: page.bounds(for: .cropBox),
                                                                            pageRotation: 180)))
      XCTAssertEqual(AnnotationSerializer.toModel(from: page.annotations[0], page: 0), model)
      for (index, size) in sizes.enumerated() {
        let image = try XCTUnwrap(page.thumbnail(of: size, for: .cropBox).cgImage)
        if type == "underline" {
          let region = CGRect(x: 0, y: image.height - 3, width: image.width, height: 3)
          XCTAssertGreaterThan(try changedPixels(baselines[index], image, within: region), 10,
                               "full-page underline must stay on the visible lower edge, render \(index)")
        } else {
          let glyph = try redBounds(image, within: CGRect(x: 0, y: 0, width: image.width, height: image.height))
          XCTAssertFalse(glyph.isNull)
          if !glyph.isNull {
            let top = try redBounds(image, within: CGRect(x: glyph.minX, y: glyph.minY,
                                                          width: glyph.width, height: glyph.height * 0.2))
            let bottom = try redBounds(image, within: CGRect(x: glyph.minX,
                                                             y: glyph.maxY - glyph.height * 0.2, width: glyph.width,
                                                             height: glyph.height * 0.2))
            XCTAssertGreaterThan(bottom.width, top.width * 1.5, "L's wide foot belongs at the visible bottom")
          }
        }
      }
    }
  }

  @MainActor private func testWindow() throws -> UIWindow {
    let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
    return try XCTUnwrap(windows.first { !$0.isHidden && $0.windowLevel == .normal }
      ?? windows.first { !$0.isHidden } ?? windows.first, "Native test host window must exist")
  }

  @MainActor private func snapshot(_ view: UIView) throws -> CGImage {
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let image = UIGraphicsImageRenderer(size: view.bounds.size, format: format).image { _ in
      view.drawHierarchy(in: view.bounds, afterScreenUpdates: false)
    }
    return try XCTUnwrap(image.cgImage)
  }

  private func changedPixels(_ before: CGImage, _ after: CGImage, within region: CGRect) throws -> Int {
    let lhs = try pixelBytes(before)
    let rhs = try pixelBytes(after)
    XCTAssertEqual(before.width, after.width)
    XCTAssertEqual(before.height, after.height)
    let clipped = region.integral.intersection(CGRect(x: 0, y: 0, width: after.width, height: after.height))
    guard !clipped.isNull else { return 0 }
    var changed = 0
    for y in Int(clipped.minY) ..< Int(clipped.maxY) {
      for x in Int(clipped.minX) ..< Int(clipped.maxX) {
        let offset = (y * after.width + x) * 4
        if (0 ..< 3).contains(where: { abs(Int(lhs[offset + $0]) - Int(rhs[offset + $0])) > 40 }) { changed += 1 }
      }
    }
    return changed
  }

  private func pixelBytes(_ image: CGImage) throws -> [UInt8] {
    let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let pixels = try XCTUnwrap(context.data).bindMemory(to: UInt8.self, capacity: image.width * image.height * 4)
    return Array(UnsafeBufferPointer(start: pixels, count: image.width * image.height * 4))
  }

  @MainActor private func assertLiveHorizontalText(_ view: ExpoPdfMarkupView, on page: PDFPage,
                                                   within visibleRegion: CGRect, file: StaticString = #filePath,
                                                   line: UInt = #line) throws {
    let nativeRegion = visibleRegion.applying(AnnotationCoordinates(page: page).visibleToNative)
    let screenRegion = view.convert(view.pdfView.convert(nativeRegion, from: page), from: view.pdfView)
    let image = try snapshot(view)
    let painted = try redBounds(image, within: screenRegion)
    XCTAssertFalse(painted.isNull, "text should paint at its live visible location", file: file, line: line)
    if !painted.isNull {
      XCTAssertGreaterThan(painted.width, painted.height * 3, file: file, line: line)
      XCTAssertGreaterThan(painted.width, view.pdfView.scaleFactor * 100, file: file, line: line)
    }
  }

  private func redBounds(_ image: CGImage, within region: CGRect) throws -> CGRect {
    let pixels = try pixelBytes(image)
    let clipped = region.integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
    guard !clipped.isNull else { return .null }
    var result = CGRect.null
    for y in Int(clipped.minY) ..< Int(clipped.maxY) {
      for x in Int(clipped.minX) ..< Int(clipped.maxX) {
        let offset = (y * image.width + x) * 4
        if pixels[offset] > 180, pixels[offset + 1] < 100, pixels[offset + 2] < 100 {
          result = result.union(CGRect(x: x, y: y, width: 1, height: 1))
        }
      }
    }
    return result
  }

  private func model(_ view: ExpoPdfMarkupView) throws -> AnnotationModel {
    try XCTUnwrap(AnnotationSerializer.deserialize(from: view.serializeCurrentAnnotations())?.annotations.first)
  }

  private func assertHorizontalText(
    _ page: PDFPage,
    near expected: CGRect,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    let image = try AnnotationTestFixture.thumbnail(page)
    let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let pixels = try XCTUnwrap(context.data).bindMemory(to: UInt8.self, capacity: image.width * image.height * 4)
    var painted = CGRect.null
    for y in Int(expected.minY) ..< Int(expected.maxY) {
      for x in Int(expected.minX) ..< Int(expected.maxX) {
        let offset = ((image.height - y) * image.width + x) * 4
        if pixels[offset] > 180, pixels[offset + 1] < 100, pixels[offset + 2] < 100 {
          painted = painted.union(CGRect(x: x, y: y, width: 1, height: 1))
        }
      }
    }
    XCTAssertFalse(painted.isNull, "text should paint at the tapped visible location", file: file, line: line)
    if !painted.isNull {
      XCTAssertGreaterThan(painted.width, 100, file: file, line: line)
      XCTAssertLessThan(painted.height, 30, file: file, line: line)
    }
  }
}

private final class RenderingTestTap: UITapGestureRecognizer {
  var point: CGPoint = .zero
  override func location(in _: UIView?) -> CGPoint {
    point
  }
}

private final class RenderingTestPan: UIPanGestureRecognizer {
  var point: CGPoint = .zero
  var suppliedState: UIGestureRecognizer.State = .possible
  override var state: UIGestureRecognizer.State {
    get { suppliedState }
    set { suppliedState = newValue }
  }

  override func location(in _: UIView?) -> CGPoint {
    point
  }
}
