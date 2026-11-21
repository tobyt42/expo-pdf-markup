@testable internal import ExpoPdfMarkup
import PDFKit
import XCTest

/// Project-owned synthetic PDFs: a raster-only page with asymmetric colored anchors,
/// plus an optional text-bearing control. No third-party document content is used.
enum AnnotationTestFixture {
  static let crop = CGRect(x: 100, y: 80, width: 600, height: 840)

  static func document(crop: CGRect = crop, rotation: Int = 0, text: Bool = false) throws -> PDFDocument {
    let media = CGRect(x: 0, y: 0, width: 800, height: 1000)
    let raster = UIGraphicsImageRenderer(size: media.size).image { context in
      UIColor.white.setFill()
      context.fill(media)
      UIColor.blue.setFill()
      context.fill(CGRect(x: 150, y: 170, width: 30, height: 50))
      UIColor.green.setFill()
      context.fill(CGRect(x: 490, y: 650, width: 60, height: 20))
    }
    let data = UIGraphicsPDFRenderer(bounds: media).pdfData { context in
      context.beginPage()
      raster.draw(in: media)
      if text { ("Selectable synthetic text" as NSString).draw(
        at: CGPoint(x: 220, y: 330),
        withAttributes: [.font: UIFont.systemFont(ofSize: 20)]
      ) }
    }
    let document = try XCTUnwrap(PDFDocument(data: data))
    let page = try XCTUnwrap(document.page(at: 0))
    page.setBounds(crop, for: .cropBox)
    page.rotation = rotation
    return document
  }

  static func thumbnail(_ page: PDFPage) throws -> CGImage {
    let box = page.bounds(for: .cropBox)
    let size = page.rotation % 180 == 0 ? box.size : CGSize(width: box.height, height: box.width)
    return try XCTUnwrap(page.thumbnail(of: size, for: .cropBox).cgImage)
  }

  static func assertRed(_ image: CGImage, x: Int, y: Int, file: StaticString = #filePath, line: UInt = #line) throws {
    let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let pixels = try XCTUnwrap(context.data).bindMemory(to: UInt8.self, capacity: image.width * image.height * 4)
    let offset = ((image.height - y) * image.width + x) * 4
    XCTAssertGreaterThan(pixels[offset], 200, file: file, line: line)
    XCTAssertLessThan(pixels[offset + 1], 80, file: file, line: line)
    XCTAssertLessThan(pixels[offset + 2], 80, file: file, line: line)
  }
}

final class AnnotationCoordinateTests: XCTestCase {
  func testRotatedTextBoundsDoNotGrowOnRepeatedRoundTrips() throws {
    let document = try AnnotationTestFixture.document(rotation: 90)
    let page = try XCTUnwrap(document.page(at: 0))
    let expected = AnnotationModel(id: "rotated-text", type: "text", page: 0, color: "#FF0000",
                                   bounds: AnnotationBounds(x: 80, y: 120, width: 240, height: 40),
                                   contents: "Visible page note",
                                   fontSize: 16, fontFamily: "Helvetica", createdAt: 123)
    var model = expected
    for _ in 0 ..< 3 {
      let annotation = try XCTUnwrap(AnnotationSerializer.toPDFAnnotation(
        model,
        pageBounds: page.bounds(for: .cropBox),
        pageRotation: page.rotation
      ))
      page.addAnnotation(annotation)
      model = try XCTUnwrap(AnnotationSerializer.toModel(from: annotation, page: 0))
      XCTAssertEqual(model, expected)
      page.removeAnnotation(annotation)
    }
  }

  @MainActor func testTextInputRequestReportsVisiblePagePoint() throws {
    let document = try AnnotationTestFixture.document()
    let page = try XCTUnwrap(document.page(at: 0))
    let view = ExpoPdfMarkupView(appContext: nil)
    view.frame = CGRect(x: 0, y: 0, width: 400, height: 700)
    view.pdfView.document = document
    view.layoutIfNeeded()
    view.pdfView.layoutDocumentView()
    view.useJsTextDialog = true
    view.setAnnotationMode("text")
    var requestedPoint: [String: CGFloat]?
    view.onTextInputRequested.onEventSent = { payload in requestedPoint = payload["point"] as? [String: CGFloat] }
    let tap = CoordinateTestTap()
    tap.suppliedLocation = view.pdfView.convert(CGPoint(x: 180, y: 200), from: page)
    view.handleTextTap(tap)
    XCTAssertEqual(try XCTUnwrap(requestedPoint?["x"]), 80, accuracy: 0.001)
    XCTAssertEqual(try XCTUnwrap(requestedPoint?["y"]), 120, accuracy: 0.001)
  }

  func testVisibleInkPlacementWithZeroOriginAndRightTopCrops() throws {
    for crop in [
      CGRect(x: 0, y: 0, width: 800, height: 1000),
      CGRect(x: 0, y: 0, width: 600, height: 840),
      AnnotationTestFixture.crop,
    ] {
      for rotation in [0, 90, 180, 270] {
        let document = try AnnotationTestFixture.document(crop: crop, rotation: rotation)
        let page = try XCTUnwrap(document.page(at: 0))
        let model = AnnotationModel(id: "control", type: "ink", page: 0, color: "#FF0000", lineWidth: 8,
                                    paths: [[["x": 80, "y": 120], ["x": 180, "y": 120]]], createdAt: 123)
        try page.addAnnotation(XCTUnwrap(AnnotationSerializer.toPDFAnnotation(
          model,
          pageBounds: crop,
          pageRotation: rotation
        )))
        try AnnotationTestFixture.assertRed(AnnotationTestFixture.thumbnail(page), x: 130, y: 120)
        XCTAssertEqual(AnnotationSerializer.toModel(from: page.annotations[0], page: 0), model)
      }
    }
  }

  @MainActor func testMoveAndOutlineUseVisibleInkGeometryAfterZoomAndScroll() throws {
    let document = try AnnotationTestFixture.document()
    let page = try XCTUnwrap(document.page(at: 0))
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 700))
    let controller = UIViewController()
    window.rootViewController = controller
    window.makeKeyAndVisible()
    let view = ExpoPdfMarkupView(appContext: nil)
    view.frame = controller.view.bounds
    controller.view.addSubview(view)
    view.pdfView.document = document
    view.layoutIfNeeded()
    view.pdfView.layoutDocumentView()
    let model = AnnotationModel(id: "moving", type: "ink", page: 0, color: "#FF0000", lineWidth: 8,
                                paths: [[["x": 80, "y": 120], ["x": 180, "y": 120]]], createdAt: 123)
    let json = try XCTUnwrap(AnnotationSerializer.serialize(AnnotationsData(annotations: [model])))
    view.loadAnnotations(from: json)
    view.pdfView.scaleFactor *= 1.5
    view.pdfScrollView?.contentOffset = CGPoint(x: 20, y: 40)
    view.setAnnotationMode("move")
    let pan = CoordinateTestPan()
    pan.suppliedLocation = view.pdfView.convert(CGPoint(x: 230, y: 200), from: page)
    pan.suppliedState = .began
    view.handleMovePan(pan)
    pan.suppliedLocation = view.pdfView.convert(CGPoint(x: 250, y: 230), from: page)
    pan.suppliedState = .changed
    view.handleMovePan(pan)
    pan.suppliedState = .ended
    view.handleMovePan(pan)
    let result = try XCTUnwrap(AnnotationSerializer.deserialize(from: view.serializeCurrentAnnotations())
      .flatMap(\.annotations.first))
    let stroke = try XCTUnwrap(result.decodedPaths.first)
    XCTAssertEqual(result.id, "moving")
    XCTAssertEqual(stroke[0].x, 100, accuracy: 0.001)
    XCTAssertEqual(stroke[0].y, 150, accuracy: 0.001)
    try AnnotationTestFixture.assertRed(AnnotationTestFixture.thumbnail(page), x: 150, y: 150)
    XCTAssertNotNil(view.hitTestAnnotation(at: CGPoint(x: 250, y: 230), on: page))
    XCTAssertNil(view.hitTestAnnotation(at: CGPoint(x: 150, y: 150), on: page))
    let documentView = try XCTUnwrap(view.pdfView.documentView)
    let expected = documentView.convert(
      view.pdfView.convert(CGRect(x: 190, y: 220, width: 120, height: 20), from: page),
      from: view.pdfView
    )
    let outline = try XCTUnwrap(view.editingOverlayLayer?.path).boundingBoxOfPath
    XCTAssertEqual(outline.minX, expected.minX, accuracy: 0.01)
    XCTAssertEqual(outline.minY, expected.minY, accuracy: 0.01)
    XCTAssertEqual(outline.width, expected.width, accuracy: 0.01)
    XCTAssertEqual(outline.height, expected.height, accuracy: 0.01)
    window.isHidden = true
  }

  func testSharedV1AnnotationsRoundTripWithoutChangingVisiblePlacementOrStyle() throws {
    let url = try XCTUnwrap(Bundle(for: type(of: self)).url(forResource: "annotations-v1", withExtension: "json"))
    let fixture = try XCTUnwrap(AnnotationSerializer.deserialize(from: String(contentsOf: url, encoding: .utf8)))
    let document = try AnnotationTestFixture.document()
    let page = try XCTUnwrap(document.page(at: 0))
    var models = fixture.annotations
    for _ in 0 ..< 3 {
      for annotation in page.annotations {
        page.removeAnnotation(annotation)
      }
      for model in models {
        try page.addAnnotation(XCTUnwrap(AnnotationSerializer.toPDFAnnotation(
          model,
          pageBounds: page.bounds(for: .cropBox)
        )))
      }
      models = page.annotations.compactMap { AnnotationSerializer.toModel(from: $0, page: 0) }
      XCTAssertEqual(models, fixture.annotations)
    }
  }

  private func sharedFixtureJSON(_ name: String) throws -> String {
    let url = try XCTUnwrap(Bundle(for: type(of: self)).url(forResource: name, withExtension: "json"))
    return try String(contentsOf: url, encoding: .utf8)
  }

  /// What PDFKit actually holds for an annotation set: native ink points and bounds.
  private func nativePlacement(of json: String, crop: CGRect, rotation: Int) throws -> [String] {
    let document = try AnnotationTestFixture.document(crop: crop, rotation: rotation)
    let page = try XCTUnwrap(document.page(at: 0))
    let data = try XCTUnwrap(AnnotationSerializer.deserialize(from: json))
    for model in data.annotations {
      try page.addAnnotation(XCTUnwrap(AnnotationSerializer.toPDFAnnotation(
        model, pageBounds: crop, pageRotation: rotation
      )))
    }
    return page.annotations.map { annotation in
      let strokes = (annotation.paths ?? []).map { path in
        var points: [String] = []
        path.cgPath.applyWithBlock { element in
          let point = element.pointee.points[0]
          points.append("\(point.x + annotation.bounds.minX),\(point.y + annotation.bounds.minY)")
        }
        return points.joined(separator: " ")
      }
      return "\(annotation.type ?? "") \(annotation.bounds) \(strokes)"
    }
  }

  func testArrayFormFixturePlacesAnnotationsLikeObjectFormOnCroppedAndRotatedPages() throws {
    let objectForm = try sharedFixtureJSON("annotations-v1")
    let arrayForm = try sharedFixtureJSON("annotations-v1-array")
    for rotation in [0, 90, 180, 270] {
      let expected = try nativePlacement(of: objectForm, crop: AnnotationTestFixture.crop, rotation: rotation)
      XCTAssertEqual(expected.count, 8)
      XCTAssertEqual(
        try nativePlacement(of: arrayForm, crop: AnnotationTestFixture.crop, rotation: rotation),
        expected,
        "rotation \(rotation)"
      )
    }
  }

  @MainActor func testArrayFormInkCanBeMovedAndErasedAndIsWrittenInObjectForm() throws {
    let document = try AnnotationTestFixture.document()
    let page = try XCTUnwrap(document.page(at: 0))
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 700))
    let controller = UIViewController()
    window.rootViewController = controller
    window.makeKeyAndVisible()
    let view = ExpoPdfMarkupView(appContext: nil)
    view.frame = controller.view.bounds
    controller.view.addSubview(view)
    view.pdfView.document = document
    view.layoutIfNeeded()
    view.pdfView.layoutDocumentView()
    view.loadAnnotations(from: """
    {"version": 1, "annotations": [{"id": "array-ink", "type": "ink", "page": 0, "color": "#FF0000",
      "lineWidth": 8, "paths": [[[80, 120], {"x": 130, "y": 120}, [180, 120]]], "createdAt": 123}]}
    """)
    view.setAnnotationMode("move")
    let pan = CoordinateTestPan()
    pan.suppliedLocation = view.pdfView.convert(CGPoint(x: 230, y: 200), from: page)
    pan.suppliedState = .began
    view.handleMovePan(pan)
    pan.suppliedLocation = view.pdfView.convert(CGPoint(x: 250, y: 230), from: page)
    pan.suppliedState = .changed
    view.handleMovePan(pan)
    pan.suppliedState = .ended
    view.handleMovePan(pan)

    let moved = view.serializeCurrentAnnotations()
    let written = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(moved.utf8)) as? [String: Any])
    let annotation = try XCTUnwrap((written["annotations"] as? [[String: Any]])?.first)
    let stroke = try XCTUnwrap((annotation["paths"] as? [[Any]])?.first as? [[String: Double]])
    XCTAssertEqual(stroke.count, 3)
    for (point, expected) in zip(stroke, [(100.0, 150.0), (150, 150), (200, 150)]) {
      XCTAssertEqual(try XCTUnwrap(point["x"]), expected.0, accuracy: 0.001)
      XCTAssertEqual(try XCTUnwrap(point["y"]), expected.1, accuracy: 0.001)
    }

    let erased = try XCTUnwrap(view.hitTestAnnotation(at: CGPoint(x: 250, y: 230), on: page))
    page.removeAnnotation(erased)
    XCTAssertEqual(try XCTUnwrap(AnnotationSerializer.deserialize(from: view.serializeCurrentAnnotations()))
      .annotations, [])
    window.isHidden = true
  }

  @MainActor func testStampsAreVisibleInLivePdfViewBeforeAndAfterReopen() throws {
    let document = try AnnotationTestFixture.document()
    let page = try XCTUnwrap(document.page(at: 0))
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 700))
    let controller = UIViewController()
    window.rootViewController = controller
    window.makeKeyAndVisible()
    let view = ExpoPdfMarkupView(appContext: nil)
    view.frame = controller.view.bounds
    controller.view.addSubview(view)
    view.pdfView.document = document
    view.layoutIfNeeded()
    view.pdfView.layoutDocumentView()
    for (index, glyph) in ["♫", "★", "🎵"].enumerated() {
      let model = AnnotationModel(id: glyph, type: "stamp", page: 0, color: "#FF0000",
                                  bounds: AnnotationBounds(x: CGFloat(20 + index * 240), y: 60, width: 48, height: 48),
                                  text: glyph)
      try page.addAnnotation(XCTUnwrap(AnnotationSerializer.toPDFAnnotation(
        model,
        pageBounds: page.bounds(for: .cropBox)
      )))
    }
    for pass in 0 ..< 2 {
      view.pdfView.setNeedsDisplay()
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
      let format = UIGraphicsImageRendererFormat()
      format.scale = 1
      let snapshot = UIGraphicsImageRenderer(size: view.bounds.size, format: format).image { _ in
        view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
      }
      let attachment = XCTAttachment(image: snapshot)
      attachment.name = "Cropped stamps live view pass \(pass)"
      attachment.lifetime = .keepAlways
      add(attachment)
      let image = try XCTUnwrap(snapshot.cgImage)
      let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height,
                                            bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                            space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
      let pixels = try XCTUnwrap(context.data).bindMemory(to: UInt8.self, capacity: image.width * image.height * 4)
      for index in 0 ..< 3 {
        let native = CGRect(x: 120 + index * 240, y: 140, width: 48, height: 48)
        let rect = view.convert(view.pdfView.convert(native, from: page), from: view.pdfView).integral
        var painted = 0
        for y in max(0, Int(rect.minY)) ..< min(image.height, Int(rect.maxY)) {
          for x in max(0, Int(rect.minX)) ..< min(image.width, Int(rect.maxX)) {
            let offset = (y * image.width + x) * 4
            if pixels[offset + 1] < 180 || pixels[offset + 2] < 180 { painted += 1 }
          }
        }
        XCTAssertGreaterThan(painted, 10, "live glyph \(index), pass \(pass)")
      }
      let json = view.serializeCurrentAnnotations()
      view.loadAnnotations(from: nil)
      view.loadAnnotations(from: json)
    }
    window.isHidden = true
  }

  func testStampGlyphsRenderAtTheirVisibleBoundsOnCroppedPage() throws {
    for glyph in ["♫", "★", "🎵"] {
      let document = try AnnotationTestFixture.document()
      let page = try XCTUnwrap(document.page(at: 0))
      let model = AnnotationModel(id: glyph, type: "stamp", page: 0, color: "#FF0000",
                                  bounds: AnnotationBounds(x: 20, y: 60, width: 48, height: 48), text: glyph)
      let annotation = try XCTUnwrap(AnnotationSerializer.toPDFAnnotation(
        model,
        pageBounds: page.bounds(for: .cropBox)
      ))
      page.addAnnotation(annotation)
      let image = try AnnotationTestFixture.thumbnail(page)
      let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height,
                                            bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                            space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
      let pixels = try XCTUnwrap(context.data).bindMemory(to: UInt8.self, capacity: image.width * image.height * 4)
      var painted = 0
      for y in 60 ..< 108 {
        for x in 20 ..< 68 {
          let offset = ((image.height - y) * image.width + x) * 4
          if pixels[offset + 1] < 200 || pixels[offset + 2] < 200 { painted += 1 }
        }
      }
      XCTAssertGreaterThan(painted, 30, "\(glyph) should paint within its intended bounds")
    }
  }

  @MainActor func testInkRenderingEditingAndSerializationOnRotatedCroppedPages() throws {
    let nativeInputs: [(Int, CGPoint, CGPoint)] = [
      (0, CGPoint(x: 180, y: 200), CGPoint(x: 280, y: 200)),
      (90, CGPoint(x: 580, y: 160), CGPoint(x: 580, y: 260)),
      (180, CGPoint(x: 620, y: 800), CGPoint(x: 520, y: 800)),
      (270, CGPoint(x: 220, y: 840), CGPoint(x: 220, y: 740)),
    ]
    for (rotation, start, end) in nativeInputs {
      let document = try AnnotationTestFixture.document(rotation: rotation)
      let page = try XCTUnwrap(document.page(at: 0))
      let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 700))
      let controller = UIViewController()
      window.rootViewController = controller
      window.makeKeyAndVisible()
      let view = ExpoPdfMarkupView(appContext: nil)
      view.frame = controller.view.bounds
      controller.view.addSubview(view)
      view.pdfView.document = document
      view.layoutIfNeeded()
      view.pdfView.layoutDocumentView()
      view.annotationLineWidth = 8
      view.setAnnotationMode("ink")
      let overlay = try XCTUnwrap(view.inkOverlayView)
      overlay.onBegan?(view.convert(view.pdfView.convert(start, from: page), from: view.pdfView))
      overlay.onMoved?(view.convert(view.pdfView.convert(end, from: page), from: view.pdfView))
      overlay.onEnded?()
      let result = try XCTUnwrap(AnnotationSerializer.deserialize(from: view.serializeCurrentAnnotations()))
      let stroke = try XCTUnwrap(result.annotations.first?.decodedPaths.first)
      XCTAssertEqual(stroke.count, 2)
      XCTAssertEqual(stroke[0].x, 80, accuracy: 0.001)
      XCTAssertEqual(stroke[0].y, 120, accuracy: 0.001)
      XCTAssertEqual(stroke[1].x, 180, accuracy: 0.001)
      XCTAssertEqual(stroke[1].y, 120, accuracy: 0.001)
      try AnnotationTestFixture.assertRed(AnnotationTestFixture.thumbnail(page), x: 130, y: 120)
      XCTAssertNotNil(view.hitTestAnnotation(at: CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2), on: page))
      window.isHidden = true
    }
  }
}

private final class CoordinateTestPan: UIPanGestureRecognizer {
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

private final class CoordinateTestTap: UITapGestureRecognizer {
  var suppliedLocation: CGPoint = .zero
  override func location(in _: UIView?) -> CGPoint {
    suppliedLocation
  }
}
