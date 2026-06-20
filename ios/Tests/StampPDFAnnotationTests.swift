@testable internal import ExpoPdfMarkup
import PDFKit
import XCTest

final class StampPDFAnnotationTests: XCTestCase {
  func testDrawWithEmojiContentDoesNotThrowAndPaintsPixels() throws {
    let bounds = CGRect(x: 0, y: 0, width: 48, height: 48)
    let annotation = StampPDFAnnotation(bounds: bounds, forType: .stamp, withProperties: nil)
    annotation.setStampContentType("emoji")
    annotation.setStampEmoji("⭐")

    let context = try XCTUnwrap(makeContext(size: bounds.size))
    annotation.draw(with: .mediaBox, in: context)

    XCTAssertTrue(hasNonTransparentPixel(context: context, size: bounds.size))
  }

  func testDrawWithMissingImageDoesNothing() throws {
    let bounds = CGRect(x: 0, y: 0, width: 48, height: 48)
    let annotation = StampPDFAnnotation(bounds: bounds, forType: .stamp, withProperties: nil)
    annotation.setStampContentType("image")
    annotation.setStampImageUri("/tmp/does-not-exist-\(UUID().uuidString).png")

    let context = try XCTUnwrap(makeContext(size: bounds.size))
    annotation.draw(with: .mediaBox, in: context)

    XCTAssertFalse(hasNonTransparentPixel(context: context, size: bounds.size))
  }

  func testDrawWithoutContentTypeDoesNothing() throws {
    let bounds = CGRect(x: 0, y: 0, width: 48, height: 48)
    let annotation = StampPDFAnnotation(bounds: bounds, forType: .stamp, withProperties: nil)

    let context = try XCTUnwrap(makeContext(size: bounds.size))
    annotation.draw(with: .mediaBox, in: context)

    XCTAssertFalse(hasNonTransparentPixel(context: context, size: bounds.size))
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
}
