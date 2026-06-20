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
