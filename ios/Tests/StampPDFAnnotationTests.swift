@testable internal import ExpoPdfMarkup
import PDFKit
import XCTest

final class StampPDFAnnotationTests: XCTestCase {
  func testDrawWithTextContentDoesNotThrowAndPaintsPixels() throws {
    let bounds = CGRect(x: 0, y: 0, width: 48, height: 48)
    let annotation = StampPDFAnnotation(bounds: bounds, forType: .stamp, withProperties: nil)
    annotation.setStampText("⭐")

    let context = try XCTUnwrap(makeContext(size: bounds.size))
    annotation.draw(with: .mediaBox, in: context)

    XCTAssertTrue(hasNonTransparentPixel(context: context, size: bounds.size))
  }

  func testDrawAppliesAnnotationColor() throws {
    let bounds = CGRect(x: 0, y: 0, width: 48, height: 48)
    let annotation = StampPDFAnnotation(bounds: bounds, forType: .stamp, withProperties: nil)
    annotation.setStampText("█")
    annotation.setValue("#FF0000", forAnnotationKey: PDFAnnotationKey(rawValue: "_color"))

    let context = try XCTUnwrap(makeContext(size: bounds.size))
    annotation.draw(with: .mediaBox, in: context)

    let pixel = try XCTUnwrap(centerPixel(context: context, size: bounds.size))
    XCTAssertGreaterThan(pixel.r, 200)
    XCTAssertLessThan(pixel.g, 50)
    XCTAssertLessThan(pixel.b, 50)
  }

  func testDrawWithoutTextDoesNothing() throws {
    let bounds = CGRect(x: 0, y: 0, width: 48, height: 48)
    let annotation = StampPDFAnnotation(bounds: bounds, forType: .stamp, withProperties: nil)

    let context = try XCTUnwrap(makeContext(size: bounds.size))
    annotation.draw(with: .mediaBox, in: context)

    XCTAssertFalse(hasNonTransparentPixel(context: context, size: bounds.size))
  }

  /// "L" is asymmetric top-to-bottom: a wide horizontal foot at the bottom of the glyph and
  /// a narrow vertical stroke at the top. A bitmap context backing draw(with:in:) stores rows
  /// top-down while PDF space is bottom-up, so an unflipped (or wrongly-flipped) draw flips the
  /// glyph vertically. Assert the foot lands near the low-y (bottom) edge of bounds, matching
  /// normal reading orientation when the page is viewed right-side up.
  func testDrawRendersTextInUprightOrientation() throws {
    let bounds = CGRect(x: 0, y: 0, width: 64, height: 64)
    let width = Int(bounds.width)
    let height = Int(bounds.height)
    let context = try XCTUnwrap(makeContext(size: bounds.size))

    let annotation = StampPDFAnnotation(bounds: bounds, forType: .stamp, withProperties: nil)
    annotation.setStampText("L")
    annotation.setValue("#000000", forAnnotationKey: PDFAnnotationKey(rawValue: "_color"))
    annotation.draw(with: .mediaBox, in: context)

    let data = try XCTUnwrap(context.data)
    let buffer = data.bindMemory(to: UInt8.self, capacity: width * height * 4)

    func inkSpan(row: Int) -> Int {
      var minX = -1
      var maxX = -1
      for x in 0 ..< width {
        let idx = (row * width + x) * 4
        if buffer[idx + 3] > 10 {
          if minX == -1 { minX = x }
          maxX = x
        }
      }
      return minX == -1 ? 0 : (maxX - minX)
    }

    var minInkRow = -1
    var maxInkRow = -1
    for row in 0 ..< height where inkSpan(row: row) > 0 {
      if minInkRow == -1 { minInkRow = row }
      maxInkRow = row
    }
    let minInkRowUnwrapped = try XCTUnwrap(minInkRow == -1 ? nil : minInkRow)
    let maxInkRowUnwrapped = try XCTUnwrap(maxInkRow == -1 ? nil : maxInkRow)

    // Buffer row 0 is the top of the bitmap (PDF-space maxY); the last row is the bottom
    // (PDF-space minY, where the page's "down" is).
    let spanNearBufferTop = inkSpan(row: minInkRowUnwrapped + 2)
    let spanNearBufferBottom = inkSpan(row: maxInkRowUnwrapped - 2)
    XCTAssertGreaterThan(
      spanNearBufferBottom, spanNearBufferTop,
      "expected the wide foot of \"L\" near the bottom of the page (low PDF y), not the top"
    )
  }

  // MARK: - Helpers

  private func makeContext(size: CGSize) -> CGContext? {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    return CGContext(
      data: nil,
      width: Int(size.width),
      height: Int(size.height),
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
  }

  private func hasNonTransparentPixel(context: CGContext, size: CGSize) -> Bool {
    guard let data = context.data else { return false }
    let byteCount = Int(size.width) * Int(size.height) * 4
    let buffer = data.bindMemory(to: UInt8.self, capacity: byteCount)
    for pixelIndex in stride(from: 0, to: byteCount, by: 4) {
      let alpha = buffer[pixelIndex + 3]
      if alpha > 0 { return true }
    }
    return false
  }

  private func centerPixel(context: CGContext, size: CGSize) -> (r: UInt8, g: UInt8, b: UInt8)? {
    guard let data = context.data else { return nil }
    let width = Int(size.width)
    let height = Int(size.height)
    let byteCount = width * height * 4
    let buffer = data.bindMemory(to: UInt8.self, capacity: byteCount)
    let pixelIndex = ((height / 2) * width + width / 2) * 4
    return (r: buffer[pixelIndex], g: buffer[pixelIndex + 1], b: buffer[pixelIndex + 2])
  }
}
