@testable internal import ExpoPdfMarkup
import XCTest

final class AnnotationModelTests: XCTestCase {
  // MARK: - Decode

  func testDecodeInkAnnotation() throws {
    let json = """
    {
      "version": 1,
      "annotations": [{
        "id": "abc-123",
        "type": "ink",
        "page": 0,
        "color": "#FF0000",
        "lineWidth": 3.0,
        "paths": [[{"x": 10, "y": 20}, {"x": 30, "y": 40}]],
        "createdAt": 1741340000
      }]
    }
    """
    let data = AnnotationSerializer.deserialize(from: json)
    XCTAssertNotNil(data)
    XCTAssertEqual(data?.version, 1)
    XCTAssertEqual(data?.annotations.count, 1)

    let annotation = try XCTUnwrap(data?.annotations[0])
    XCTAssertEqual(annotation.id, "abc-123")
    XCTAssertEqual(annotation.type, "ink")
    XCTAssertEqual(annotation.page, 0)
    XCTAssertEqual(annotation.color, "#FF0000")
    XCTAssertEqual(annotation.lineWidth, 3.0)
    XCTAssertEqual(annotation.decodedPaths.count, 1)
    XCTAssertEqual(annotation.decodedPaths[0].count, 2)
    XCTAssertEqual(annotation.decodedPaths[0][0], AnnotationPoint(x: 10, y: 20))
  }

  func testDecodeHighlightAnnotation() throws {
    let json = """
    {
      "version": 1,
      "annotations": [{
        "id": "def-456",
        "type": "highlight",
        "page": 1,
        "color": "#FFFF00",
        "alpha": 0.5,
        "bounds": {"x": 72, "y": 340, "width": 200, "height": 14},
        "createdAt": 1741340000
      }]
    }
    """
    let data = AnnotationSerializer.deserialize(from: json)
    XCTAssertNotNil(data)
    let annotation = try XCTUnwrap(data?.annotations[0])
    XCTAssertEqual(annotation.type, "highlight")
    XCTAssertEqual(annotation.alpha, 0.5)
    XCTAssertEqual(annotation.bounds, AnnotationBounds(x: 72, y: 340, width: 200, height: 14))
  }

  func testDecodeUnderlineAnnotation() {
    let json = """
    {
      "version": 1,
      "annotations": [{
        "id": "ghi-789",
        "type": "underline",
        "page": 0,
        "color": "#0000FF",
        "bounds": {"x": 50, "y": 100, "width": 150, "height": 12}
      }]
    }
    """
    let data = AnnotationSerializer.deserialize(from: json)
    XCTAssertNotNil(data)
    XCTAssertEqual(data?.annotations[0].type, "underline")
    XCTAssertNil(data?.annotations[0].alpha)
  }

  func testDecodeTextAnnotation() {
    let json = """
    {
      "version": 1,
      "annotations": [{
        "id": "txt-001",
        "type": "text",
        "page": 2,
        "color": "#00FF00",
        "bounds": {"x": 100, "y": 200, "width": 24, "height": 24},
        "contents": "My note"
      }]
    }
    """
    let data = AnnotationSerializer.deserialize(from: json)
    XCTAssertNotNil(data)
    XCTAssertEqual(data?.annotations[0].type, "text")
    XCTAssertEqual(data?.annotations[0].contents, "My note")
  }

  func testDecodeMixedAnnotations() {
    let json = """
    {
      "version": 1,
      "annotations": [
        {"id": "1", "type": "ink", "page": 0, "color": "#FF0000", "lineWidth": 2,
         "paths": [[{"x": 0, "y": 0}]]},
        {"id": "2", "type": "highlight", "page": 0, "color": "#FFFF00",
         "bounds": {"x": 0, "y": 0, "width": 100, "height": 10}},
        {"id": "3", "type": "text", "page": 1, "color": "#00FF00",
         "bounds": {"x": 50, "y": 50, "width": 24, "height": 24}, "contents": "Hi"}
      ]
    }
    """
    let data = AnnotationSerializer.deserialize(from: json)
    XCTAssertNotNil(data)
    XCTAssertEqual(data?.annotations.count, 3)
    XCTAssertEqual(data?.annotations[0].type, "ink")
    XCTAssertEqual(data?.annotations[1].type, "highlight")
    XCTAssertEqual(data?.annotations[2].type, "text")
  }

  func testDecodeInvalidJSON() {
    let data = AnnotationSerializer.deserialize(from: "not json at all")
    XCTAssertNil(data)
  }

  func testDecodeEmptyAnnotations() {
    let json = """
    {"version": 1, "annotations": []}
    """
    let data = AnnotationSerializer.deserialize(from: json)
    XCTAssertNotNil(data)
    XCTAssertEqual(data?.annotations.count, 0)
  }

  // MARK: - Round-trip

  func testEncodeDecodeRoundTrip() {
    let original = AnnotationsData(
      version: 1,
      annotations: [
        AnnotationModel(
          id: "rt-1",
          type: "ink",
          page: 0,
          color: "#FF0000",
          lineWidth: 2.5,
          paths: [[["x": 10, "y": 20], ["x": 30, "y": 40]]],
          createdAt: 1_741_340_000
        ),
        AnnotationModel(
          id: "rt-2",
          type: "highlight",
          page: 1,
          color: "#FFFF00",
          alpha: 0.5,
          bounds: AnnotationBounds(x: 72, y: 340, width: 200, height: 14),
          createdAt: 1_741_340_000
        ),
      ]
    )

    guard let json = AnnotationSerializer.serialize(original) else {
      XCTFail("Failed to serialize")
      return
    }

    guard let decoded = AnnotationSerializer.deserialize(from: json) else {
      XCTFail("Failed to deserialize")
      return
    }

    XCTAssertEqual(decoded.version, original.version)
    XCTAssertEqual(decoded.annotations.count, original.annotations.count)
    XCTAssertEqual(decoded.annotations[0].id, "rt-1")
    XCTAssertEqual(decoded.annotations[1].id, "rt-2")
  }
}
