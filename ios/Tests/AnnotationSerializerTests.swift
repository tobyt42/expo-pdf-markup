@testable internal import ExpoPdfMarkup
import PDFKit
import XCTest

final class AnnotationSerializerTests: XCTestCase {
  func testCroppedPageInkRendersAtVisiblePageCoordinates() throws {
    let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 800, height: 1000))
    let document = try XCTUnwrap(PDFDocument(data: renderer.pdfData { context in
      context.beginPage()
      UIColor.white.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 800, height: 1000))
    }))
    let page = try XCTUnwrap(document.page(at: 0))
    page.setBounds(CGRect(x: 100, y: 80, width: 600, height: 840), for: .cropBox)
    let model = AnnotationModel(
      id: "crop-ink", type: "ink", page: 0, color: "#FF0000", lineWidth: 8,
      paths: [[["x": 80, "y": 120], ["x": 180, "y": 120]]], createdAt: 123
    )
    let annotation = try XCTUnwrap(AnnotationSerializer.toPDFAnnotation(model, pageBounds: page.bounds(for: .cropBox)))
    page.addAnnotation(annotation)
    let image = try XCTUnwrap(page.thumbnail(of: CGSize(width: 600, height: 840), for: .cropBox).cgImage)
    let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let pixels = try XCTUnwrap(context.data).bindMemory(to: UInt8.self, capacity: image.width * image.height * 4)
    // The midpoint is 130 pt from the visible left and 120 pt from the visible bottom.
    let offset = ((image.height - 120) * image.width + 130) * 4
    XCTAssertGreaterThan(pixels[offset], 200)
    XCTAssertLessThan(pixels[offset + 1], 80)
    XCTAssertLessThan(pixels[offset + 2], 80)
  }

  func testRectangularModelsUseVisiblePageCoordinatesOnCroppedPages() throws {
    let crop = CGRect(x: 100, y: 80, width: 600, height: 840)
    for type in ["highlight", "underline", "freeText", "stamp"] {
      let model = AnnotationModel(id: "crop-\(type)", type: type, page: 0, color: "#FF0000",
                                  bounds: AnnotationBounds(x: 80, y: 120, width: 100, height: 48), contents: "A",
                                  text: "♫")
      let annotation = try XCTUnwrap(AnnotationSerializer.toPDFAnnotation(model, pageBounds: crop))
      let contentBounds = (annotation as? AreaUnderlinePDFAnnotation)?
        .contentBounds ?? (annotation as? StampPDFAnnotation)?.contentBounds ?? annotation.bounds
      XCTAssertEqual(contentBounds, CGRect(x: 180, y: 200, width: 100, height: 48), type)
    }
  }

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
    XCTAssertEqual(annotation.flatMap { AnnotationSerializer.toModel(from: $0, page: 0) }?.type, "underline")
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
    // PDFKit may normalize a transparent background to no color on newer iOS versions.
    let backgroundColor: UIColor? = annotation?.color
    XCTAssertEqual(backgroundColor?.cgColor.alpha ?? 0, 0)
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

  func testCreateStampAnnotationWithText() throws {
    let model = AnnotationModel(
      id: "st-1",
      type: "stamp",
      page: 0,
      color: "#000000",
      bounds: AnnotationBounds(x: 10, y: 20, width: 48, height: 48),
      text: "⭐"
    )

    let annotation = AnnotationSerializer.toPDFAnnotation(model)
    XCTAssertNotNil(annotation)
    XCTAssertEqual(annotation?.type, "Stamp")
    XCTAssertTrue(annotation is StampPDFAnnotation)
    XCTAssertTrue(try AnnotationSerializer.isModuleManaged(XCTUnwrap(annotation)))
  }

  func testStampMissingBoundsReturnsNil() {
    let model = AnnotationModel(
      id: "st-3",
      type: "stamp",
      page: 0,
      color: "#000000",
      text: "⭐"
    )

    let annotation = AnnotationSerializer.toPDFAnnotation(model)
    XCTAssertNil(annotation)
  }

  func testStampMissingTextReturnsNil() {
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
    XCTAssertEqual(
      result.decodedPaths,
      [[AnnotationPoint(x: 10, y: 20), AnnotationPoint(x: 30, y: 40)]]
    )
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
      text: "⭐"
    )

    let pdfAnnotation = try XCTUnwrap(AnnotationSerializer.toPDFAnnotation(model))
    let extracted = AnnotationSerializer.toModel(from: pdfAnnotation, page: 0)

    let result = try XCTUnwrap(extracted)
    XCTAssertEqual(result.type, "stamp")
    XCTAssertEqual(result.text, "⭐")
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

  // MARK: - Ink point forms

  private func sharedFixture(_ name: String) throws -> AnnotationsData {
    let url = try XCTUnwrap(Bundle(for: type(of: self)).url(forResource: name, withExtension: "json"))
    return try XCTUnwrap(AnnotationSerializer.deserialize(from: String(contentsOf: url, encoding: .utf8)))
  }

  func testArrayFormFixtureDecodesToTheSameAnnotationsAsObjectFormFixture() throws {
    XCTAssertEqual(try sharedFixture("annotations-v1-array"), try sharedFixture("annotations-v1"))
  }

  func testMalformedInkPointsAreSkippedAndTheRestOfTheSetLoads() throws {
    let json = """
    {"version": 1, "annotations": [
      {"id": "ink", "type": "ink", "page": 0, "color": "#FF0000", "lineWidth": 2,
       "paths": [[[1, 2], [3], [4, 5, 6], ["a", "b"], {"x": 7}, {"x": "8", "y": 9}, null, true, 10,
                  {"x": 11.5, "y": 12}, [13, 14.25]]]},
      {"id": "hl", "type": "highlight", "page": 1, "color": "#FFCC00",
       "bounds": {"x": 1, "y": 2, "width": 3, "height": 4}}
    ]}
    """
    let data = try XCTUnwrap(AnnotationSerializer.deserialize(from: json))
    XCTAssertEqual(data.annotations.map(\.id), ["ink", "hl"])
    XCTAssertEqual(data.annotations[0].decodedPaths, [[
      AnnotationPoint(x: 1, y: 2), AnnotationPoint(x: 11.5, y: 12), AnnotationPoint(x: 13, y: 14.25),
    ]])
    XCTAssertEqual(data.annotations[1].bounds, AnnotationBounds(x: 1, y: 2, width: 3, height: 4))
  }

  func testArrayFormInkIsWrittenBackInObjectForm() throws {
    let data = try XCTUnwrap(AnnotationSerializer.deserialize(from: """
    {"version": 1, "annotations": [{"id": "ink", "type": "ink", "page": 0, "color": "#FF0000",
      "paths": [[[40, 100], {"x": 120, "y": 160}, [180, 130]]]}]}
    """))
    let json = try XCTUnwrap(AnnotationSerializer.serialize(data))
    let written = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    let annotation = try XCTUnwrap((written["annotations"] as? [[String: Any]])?.first)
    let stroke = try XCTUnwrap((annotation["paths"] as? [[Any]])?.first as? [[String: Double]])
    XCTAssertEqual(stroke, [["x": 40, "y": 100], ["x": 120, "y": 160], ["x": 180, "y": 130]])
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
