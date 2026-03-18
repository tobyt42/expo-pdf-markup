@testable internal import ExpoPdfMarkup
import PDFKit
import XCTest

final class AnnotationSerializerTests: XCTestCase {
  // MARK: - PDFAnnotation creation

  func testCreateInkAnnotation() throws {
    let model = AnnotationModel(
      id: "ink-1",
      type: "ink",
      page: 0,
      color: "#FF0000",
      lineWidth: 3.0,
      paths: [[["x": 10, "y": 20], ["x": 30, "y": 40]]],
      createdAt: 1_741_340_000
    )

    let annotation = AnnotationSerializer.toPDFAnnotation(model)
    XCTAssertNotNil(annotation)
    XCTAssertEqual(annotation?.type, "Ink")
    XCTAssertEqual(annotation?.border?.lineWidth, 3.0)
    XCTAssertTrue(try AnnotationSerializer.isModuleManaged(XCTUnwrap(annotation)))
  }

  func testCreateHighlightAnnotation() {
    let model = AnnotationModel(
      id: "hl-1",
      type: "highlight",
      page: 0,
      color: "#FFFF00",
      alpha: 0.5,
      bounds: AnnotationBounds(x: 72, y: 340, width: 200, height: 14),
      createdAt: 1_741_340_000
    )

    let annotation = AnnotationSerializer.toPDFAnnotation(model)
    XCTAssertNotNil(annotation)
    XCTAssertEqual(annotation?.type, "Highlight")
    XCTAssertEqual(annotation?.bounds, CGRect(x: 72, y: 340, width: 200, height: 14))
  }

  func testCreateUnderlineAnnotation() {
    let model = AnnotationModel(
      id: "ul-1",
      type: "underline",
      page: 0,
      color: "#0000FF",
      bounds: AnnotationBounds(x: 50, y: 100, width: 150, height: 12)
    )

    let annotation = AnnotationSerializer.toPDFAnnotation(model)
    XCTAssertNotNil(annotation)
    XCTAssertEqual(annotation?.type, "Underline")
  }

  func testCreateFreeTextAnnotation() {
    let model = AnnotationModel(
      id: "txt-1",
      type: "freeText",
      page: 0,
      color: "#00FF00",
      bounds: AnnotationBounds(x: 100, y: 200, width: 200, height: 24),
      contents: "My note",
      fontSize: 16.0
    )

    let annotation = AnnotationSerializer.toPDFAnnotation(model)
    XCTAssertNotNil(annotation)
    XCTAssertEqual(annotation?.type, "FreeText")
    XCTAssertEqual(annotation?.contents, "My note")
    XCTAssertEqual(annotation?.font?.pointSize, 16.0)
    XCTAssertEqual(annotation?.color, .clear)
  }

  func testCreateFreeTextAnnotationExpandsNarrowBoundsToFitText() {
    let originalBounds = AnnotationBounds(x: 100, y: 200, width: 40, height: 24)
    let model = AnnotationModel(
      id: "txt-narrow-1",
      type: "freeText",
      page: 0,
      color: "#00FF00",
      bounds: originalBounds,
      contents: "Hello from Android",
      fontSize: 16.0
    )

    let annotation = AnnotationSerializer.toPDFAnnotation(model)
    XCTAssertNotNil(annotation)
    XCTAssertGreaterThan(annotation?.bounds.width ?? 0, originalBounds.width)
    XCTAssertEqual(annotation?.bounds.maxY, originalBounds.cgRect.maxY, accuracy: 0.01)
  }

  func testUnknownTypeReturnsNil() {
    let model = AnnotationModel(
      id: "bad-1",
      type: "unknown",
      page: 0,
      color: "#000000"
    )

    let annotation = AnnotationSerializer.toPDFAnnotation(model)
    XCTAssertNil(annotation)
  }

  // MARK: - Model extraction

  func testExtractModelFromModuleManagedAnnotation() {
    let model = AnnotationModel(
      id: "ext-1",
      type: "ink",
      page: 0,
      color: "#FF0000",
      lineWidth: 2.0,
      paths: [[["x": 10, "y": 20], ["x": 30, "y": 40]]],
      createdAt: 1_741_340_000
    )

    let pdfAnnotation = try XCTUnwrap(AnnotationSerializer.toPDFAnnotation(model))
    let extracted = AnnotationSerializer.toModel(from: pdfAnnotation, page: 0)

    XCTAssertNotNil(extracted)
    let result = try XCTUnwrap(extracted)
    XCTAssertEqual(result.id, "ext-1")
    XCTAssertEqual(result.type, "ink")
    XCTAssertEqual(result.page, 0)
    XCTAssertEqual(result.color, "#FF0000")
  }

  func testFreeTextColorRoundTrip() {
    let model = AnnotationModel(
      id: "ft-color-1",
      type: "freeText",
      page: 0,
      color: "#FF0000",
      bounds: AnnotationBounds(x: 10, y: 10, width: 100, height: 20),
      contents: "Red text",
      fontSize: 14.0,
      createdAt: 1_741_340_000
    )

    let pdfAnnotation = try XCTUnwrap(AnnotationSerializer.toPDFAnnotation(model))
    let extracted = AnnotationSerializer.toModel(from: pdfAnnotation, page: 0)

    XCTAssertNotNil(extracted)
    let result = try XCTUnwrap(extracted)
    XCTAssertEqual(result.color, "#FF0000", "freeText color must survive a serialisation round-trip")
  }

  func testExtractModelFromNonManagedAnnotationReturnsNil() {
    let annotation = PDFAnnotation(
      bounds: CGRect(x: 0, y: 0, width: 100, height: 10),
      forType: .highlight,
      withProperties: nil
    )
    let extracted = AnnotationSerializer.toModel(from: annotation, page: 0)
    XCTAssertNil(extracted)
  }

  // MARK: - Ownership filtering

  func testOwnershipFiltering() {
    let managed = PDFAnnotation(
      bounds: CGRect(x: 0, y: 0, width: 100, height: 10),
      forType: .highlight,
      withProperties: nil
    )
    AnnotationSerializer.tagAsModuleManaged(managed, id: "owned-1", createdAt: 1_741_340_000)

    let embedded = PDFAnnotation(
      bounds: CGRect(x: 0, y: 0, width: 100, height: 10),
      forType: .highlight,
      withProperties: nil
    )

    XCTAssertTrue(AnnotationSerializer.isModuleManaged(managed))
    XCTAssertFalse(AnnotationSerializer.isModuleManaged(embedded))
  }

  // MARK: - Color helpers

  func testColorFromHex() {
    let red = try XCTUnwrap(AnnotationSerializer.colorFromHex("#FF0000"))

    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    red.getRed(&r, green: &g, blue: &b, alpha: &a)
    XCTAssertEqual(r, 1.0, accuracy: 0.01)
    XCTAssertEqual(g, 0.0, accuracy: 0.01)
    XCTAssertEqual(b, 0.0, accuracy: 0.01)
  }

  func testColorFromHexWithoutHash() {
    let blue = try XCTUnwrap(AnnotationSerializer.colorFromHex("0000FF"))

    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    blue.getRed(&r, green: &g, blue: &b, alpha: &a)
    XCTAssertEqual(b, 1.0, accuracy: 0.01)
  }

  func testColorFromInvalidHex() {
    XCTAssertNil(AnnotationSerializer.colorFromHex("xyz"))
    XCTAssertNil(AnnotationSerializer.colorFromHex("#GG0000"))
    XCTAssertNil(AnnotationSerializer.colorFromHex(""))
  }

  func testHexFromColor() {
    let hex = AnnotationSerializer.hexFromColor(.red)
    XCTAssertEqual(hex, "#FF0000")
  }

  func testHexRoundTrip() {
    let original = "#3366CC"
    guard let color = AnnotationSerializer.colorFromHex(original) else {
      XCTFail("Failed to parse hex")
      return
    }
    let result = AnnotationSerializer.hexFromColor(color)
    XCTAssertEqual(result, original)
  }

  // MARK: - extractNativeAnnotation

  func testExtractNativeInkAnnotation() throws {
    let annotation = PDFAnnotation(
      bounds: CGRect(x: 0, y: 0, width: 200, height: 200),
      forType: .ink,
      withProperties: nil
    )
    annotation.color = .red
    let path = UIBezierPath()
    path.move(to: CGPoint(x: 10, y: 20))
    path.addLine(to: CGPoint(x: 30, y: 40))
    annotation.add(path)

    let model = AnnotationSerializer.extractNativeAnnotation(from: annotation, pageIndex: 0)

    XCTAssertNotNil(model)
    let result = try XCTUnwrap(model)
    XCTAssertEqual(result.type, "ink")
    XCTAssertNotNil(result.paths)
    XCTAssertFalse(result.id.isEmpty)
  }

  func testExtractNativeInkAnnotationOffsetsByBoundsOriginWhenPathsAppearRelative() throws {
    // Simulates non-conforming InkList coords: relative to the annotation Rect origin
    // rather than in absolute PDF page space. PDFKit returns them as-is, so we must
    // detect and correct the offset ourselves.
    let origin = CGPoint(x: 100, y: 200)
    let annotation = PDFAnnotation(
      bounds: CGRect(origin: origin, size: CGSize(width: 80, height: 80)),
      forType: .ink,
      withProperties: nil
    )
    // Path points in annotation-local space (within [0, 80] × [0, 80])
    let path = UIBezierPath()
    path.move(to: CGPoint(x: 10, y: 10))
    path.addLine(to: CGPoint(x: 70, y: 70))
    annotation.add(path)

    let model = try XCTUnwrap(AnnotationSerializer.extractNativeAnnotation(from: annotation, pageIndex: 0))

    // Expect points offset by bounds.origin → (110, 210) and (170, 270)
    let points = try XCTUnwrap(model.paths?.first)
    XCTAssertEqual(points[0]["x"] ?? 0, origin.x + 10, accuracy: 0.01)
    XCTAssertEqual(points[0]["y"] ?? 0, origin.y + 10, accuracy: 0.01)
    XCTAssertEqual(points[1]["x"] ?? 0, origin.x + 70, accuracy: 0.01)
    XCTAssertEqual(points[1]["y"] ?? 0, origin.y + 70, accuracy: 0.01)
  }

  func testExtractNativeInkAnnotationDoesNotOffsetWhenPathsAreAbsolute() throws {
    // A conforming PDF stores InkList in absolute page space. Points extend well beyond
    // [0, bounds.width] × [0, bounds.height], so the heuristic leaves them untouched.
    let annotation = PDFAnnotation(
      bounds: CGRect(x: 100, y: 200, width: 80, height: 80),
      forType: .ink,
      withProperties: nil
    )
    // Absolute page-space points: clearly outside [0, 80] × [0, 80]
    let path = UIBezierPath()
    path.move(to: CGPoint(x: 110, y: 210))
    path.addLine(to: CGPoint(x: 170, y: 270))
    annotation.add(path)

    let model = try XCTUnwrap(AnnotationSerializer.extractNativeAnnotation(from: annotation, pageIndex: 0))

    let points = try XCTUnwrap(model.paths?.first)
    XCTAssertEqual(points[0]["x"] ?? 0, 110, accuracy: 0.01)
    XCTAssertEqual(points[0]["y"] ?? 0, 210, accuracy: 0.01)
  }

  func testExtractNativeHighlightAnnotation() throws {
    let annotation = PDFAnnotation(
      bounds: CGRect(x: 72, y: 100, width: 200, height: 14),
      forType: .highlight,
      withProperties: nil
    )
    annotation.color = UIColor.yellow.withAlphaComponent(0.5)

    let model = AnnotationSerializer.extractNativeAnnotation(from: annotation, pageIndex: 1)

    XCTAssertNotNil(model)
    let result = try XCTUnwrap(model)
    XCTAssertEqual(result.type, "highlight")
    XCTAssertNotNil(result.bounds)
    XCTAssertEqual(result.page, 1)
    XCTAssertFalse(result.id.isEmpty)
  }

  func testExtractNativeFreeTextAnnotation() throws {
    let annotation = PDFAnnotation(
      bounds: CGRect(x: 72, y: 320, width: 200, height: 20),
      forType: .freeText,
      withProperties: nil
    )
    annotation.contents = "Hello world"
    annotation.fontColor = .black

    let model = AnnotationSerializer.extractNativeAnnotation(from: annotation, pageIndex: 0)

    XCTAssertNotNil(model)
    let result = try XCTUnwrap(model)
    XCTAssertEqual(result.type, "freeText")
    XCTAssertEqual(result.contents, "Hello world")
  }

  func testExtractNativeLinkAnnotationReturnsNil() {
    let annotation = PDFAnnotation(
      bounds: CGRect(x: 0, y: 0, width: 100, height: 20),
      forType: .link,
      withProperties: nil
    )

    let model = AnnotationSerializer.extractNativeAnnotation(from: annotation, pageIndex: 0)

    XCTAssertNil(model)
  }

  func testExtractNativeAnnotationReturnsNonEmptyId() throws {
    let annotation = PDFAnnotation(
      bounds: CGRect(x: 0, y: 0, width: 100, height: 20),
      forType: .highlight,
      withProperties: nil
    )

    let model = AnnotationSerializer.extractNativeAnnotation(from: annotation, pageIndex: 0)

    XCTAssertNotNil(model)
    XCTAssertFalse(try XCTUnwrap(model?.id.isEmpty))
  }

  // MARK: - extractAllNativeAnnotations

  func testExtractAllNativeAnnotationsSkipsModuleManaged() {
    let document = PDFDocument()
    let page = PDFPage()
    document.insert(page, at: 0)

    let embedded = PDFAnnotation(
      bounds: CGRect(x: 0, y: 0, width: 100, height: 20),
      forType: .highlight,
      withProperties: nil
    )
    page.addAnnotation(embedded)

    let managed = PDFAnnotation(
      bounds: CGRect(x: 0, y: 0, width: 100, height: 20),
      forType: .highlight,
      withProperties: nil
    )
    AnnotationSerializer.tagAsModuleManaged(managed, id: "owned", createdAt: 1_000_000)
    page.addAnnotation(managed)

    let result = AnnotationSerializer.extractAllNativeAnnotations(from: document)

    // Only the non-module-managed annotation should be extracted
    XCTAssertEqual(result.annotations.count, 1)
    XCTAssertFalse(AnnotationSerializer.isModuleManaged(embedded))
  }

  func testExtractAllNativeAnnotationsEmptyDocument() {
    let document = PDFDocument()

    let result = AnnotationSerializer.extractAllNativeAnnotations(from: document)

    XCTAssertEqual(result.version, 1)
    XCTAssertTrue(result.annotations.isEmpty)
  }
}
