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

  func testCreateFreeTextAnnotationExpandsNarrowBoundsToFitText() throws {
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
    XCTAssertEqual(try XCTUnwrap(annotation).bounds.maxY, originalBounds.cgRect.maxY, accuracy: 0.01)
  }

  func testCreateStampAnnotationWithEmoji() throws {
    let model = AnnotationModel(
      id: "st-1",
      type: "stamp",
      page: 0,
      color: "#000000",
      bounds: AnnotationBounds(x: 10, y: 20, width: 48, height: 48),
      contentType: "emoji",
      emoji: "⭐"
    )

    let annotation = AnnotationSerializer.toPDFAnnotation(model)
    XCTAssertNotNil(annotation)
    XCTAssertEqual(annotation?.type, "Stamp")
    XCTAssertTrue(annotation is StampPDFAnnotation)
    XCTAssertTrue(try AnnotationSerializer.isModuleManaged(XCTUnwrap(annotation)))
  }

  func testCreateStampAnnotationWithImage() {
    let model = AnnotationModel(
      id: "st-2",
      type: "stamp",
      page: 0,
      color: "#000000",
      bounds: AnnotationBounds(x: 10, y: 20, width: 48, height: 48),
      contentType: "image",
      imageUri: "/tmp/does-not-exist.png"
    )

    let annotation = AnnotationSerializer.toPDFAnnotation(model)
    XCTAssertNotNil(annotation)
    XCTAssertEqual(annotation?.type, "Stamp")
    XCTAssertTrue(annotation is StampPDFAnnotation)
  }

  func testStampMissingBoundsReturnsNil() {
    let model = AnnotationModel(
      id: "st-3",
      type: "stamp",
      page: 0,
      color: "#000000",
      contentType: "emoji",
      emoji: "⭐"
    )

    let annotation = AnnotationSerializer.toPDFAnnotation(model)
    XCTAssertNil(annotation)
  }

  func testStampMissingContentTypeReturnsNil() {
    let model = AnnotationModel(
      id: "st-4",
      type: "stamp",
      page: 0,
      color: "#000000",
      bounds: AnnotationBounds(x: 10, y: 20, width: 48, height: 48)
    )

    let annotation = AnnotationSerializer.toPDFAnnotation(model)
    XCTAssertNil(annotation)
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

  func testExtractModelFromModuleManagedAnnotation() throws {
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

  func testFreeTextColorRoundTrip() throws {
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

  func testExtractStampModelRoundTrip() throws {
    let model = AnnotationModel(
      id: "st-rt-1",
      type: "stamp",
      page: 0,
      color: "#123456",
      bounds: AnnotationBounds(x: 10, y: 20, width: 48, height: 48),
      contentType: "emoji",
      emoji: "⭐"
    )

    let pdfAnnotation = try XCTUnwrap(AnnotationSerializer.toPDFAnnotation(model))
    let extracted = AnnotationSerializer.toModel(from: pdfAnnotation, page: 0)

    let result = try XCTUnwrap(extracted)
    XCTAssertEqual(result.type, "stamp")
    XCTAssertEqual(result.contentType, "emoji")
    XCTAssertEqual(result.emoji, "⭐")
    XCTAssertNil(result.imageUri)
    XCTAssertEqual(result.color, "#123456")
    XCTAssertEqual(result.bounds?.cgRect, CGRect(x: 10, y: 20, width: 48, height: 48))
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

  func testColorFromHex() throws {
    let red = try XCTUnwrap(AnnotationSerializer.colorFromHex("#FF0000"))

    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    red.getRed(&r, green: &g, blue: &b, alpha: &a)
    XCTAssertEqual(r, 1.0, accuracy: 0.01)
    XCTAssertEqual(g, 0.0, accuracy: 0.01)
    XCTAssertEqual(b, 0.0, accuracy: 0.01)
  }

  func testColorFromHexWithoutHash() throws {
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
}
