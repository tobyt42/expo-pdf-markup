import PDFKit
import UIKit

enum AnnotationSerializer {
  static let ownershipKey = "_expoPdfMarkup"

  // MARK: - JSON ↔ AnnotationsData

  static func deserialize(from json: String) -> AnnotationsData? {
    guard let data = json.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(AnnotationsData.self, from: data)
  }

  static func serialize(_ annotationsData: AnnotationsData) -> String? {
    guard let data = try? JSONEncoder().encode(annotationsData) else { return nil }
    return String(data: data, encoding: .utf8)
  }

  // MARK: - PDFAnnotation ↔ AnnotationModel

  static func toPDFAnnotation(_ model: AnnotationModel, pageBounds: CGRect? = nil,
                              pageRotation: Int = 0) -> PDFAnnotation? {
    let coordinates = AnnotationCoordinates(bounds: pageBounds ?? .zero, rotation: pageRotation)
    var visibleModel = model
    if model.type == "text" || model.type == "freeText", let bounds = model.bounds {
      let size = model.fontSize ?? 16
      let font = UIFont(name: model.fontFamily ?? "", size: size) ?? UIFont.systemFont(ofSize: size)
      visibleModel.bounds = AnnotationBounds(normalizedFreeTextBounds(
        bounds: bounds.cgRect,
        text: model.contents ?? "",
        font: font
      ))
    }
    let model = coordinates.transform(visibleModel, using: coordinates.visibleToNative)
    let color = colorFromHex(model.color) ?? .red

    switch model.type {
    case "ink":
      return createInkAnnotation(model: model, color: color, pageBounds: pageBounds)
    case "highlight":
      return createMarkupAnnotation(model: model, color: color, subtype: .highlight)
    case "underline":
      return createMarkupAnnotation(model: model, color: color, subtype: .underline)
    case "text", "freeText":
      return createFreeTextAnnotation(model: model, color: color)
    case "stamp":
      return createStampAnnotation(model: model)
    default:
      return nil
    }
  }

  static func toModel(from annotation: PDFAnnotation, page: Int) -> AnnotationModel? {
    guard isModuleManaged(annotation) else { return nil }
    guard let id = annotation.value(forAnnotationKey: PDFAnnotationKey(rawValue: "_id")) as? String else {
      return nil
    }
    let createdAt = annotation.value(
      forAnnotationKey: PDFAnnotationKey(rawValue: "_createdAt")
    ) as? Double ?? Date().timeIntervalSince1970

    guard let nativeType = modelType(for: annotation.type) else { return nil }
    let type = annotation.value(forAnnotationKey: PDFAnnotationKey(rawValue: "_modelType")) as? String ?? nativeType
    var model = AnnotationModel(
      id: id,
      type: type,
      page: page,
      color: colorHex(for: annotation, type: type),
      createdAt: createdAt
    )

    populateModelDetails(&model, from: annotation)
    let coordinates = annotation.page.map { AnnotationCoordinates(page: $0) } ?? AnnotationCoordinates(bounds: .zero)
    return coordinates.transform(model, using: coordinates.nativeToVisible)
  }

  private static func modelType(for annotationType: String?) -> String? {
    switch annotationType {
    case "Ink":
      "ink"
    case "Highlight":
      "highlight"
    case "Underline":
      "underline"
    case "Text":
      "text"
    case "FreeText":
      "freeText"
    case "Stamp":
      "stamp"
    default:
      nil
    }
  }

  private static func colorHex(for annotation: PDFAnnotation, type: String) -> String {
    if let storedHex = annotation.value(forAnnotationKey: PDFAnnotationKey(rawValue: "_color")) as? String {
      return storedHex
    }

    let effectiveColor: UIColor = if type == "text" || type == "freeText" {
      annotation.fontColor ?? annotation.color ?? .black
    } else {
      annotation.color ?? .red
    }

    return hexFromColor(effectiveColor)
  }

  private static func populateModelDetails(_ model: inout AnnotationModel, from annotation: PDFAnnotation) {
    switch model.type {
    case "ink":
      model.lineWidth = annotation.border?.lineWidth ?? 2.0
      // Always emit `paths`, even when PDFKit hands back nothing. The JS `Annotation`
      // type declares it non-optional, and `JSONEncoder` drops nil keys entirely, so a
      // nil here reaches consumers as a missing property rather than an empty stroke list.
      model.paths = (annotation.paths ?? []).map { path in
        pointsFromBezierPath(path).map { ["x": $0.x + annotation.bounds.minX, "y": $0.y + annotation.bounds.minY] }
      }
    case "highlight", "underline":
      model.bounds = AnnotationBounds(annotation.bounds)
      if model.type == "highlight" {
        model.alpha = annotation.color.cgColor.alpha
      }
    case "text", "freeText":
      model.bounds = AnnotationBounds(annotation.bounds)
      model.contents = annotation.contents
      if let font = annotation.font {
        model.fontSize = font.pointSize
        model.fontFamily = font.fontName
      }
    case "stamp":
      model.bounds = AnnotationBounds(annotation.bounds)
      if let stamp = annotation as? StampPDFAnnotation {
        model.text = stamp.stampText
      }
    default:
      break
    }
  }

  // MARK: - Ownership

  static func isModuleManaged(_ annotation: PDFAnnotation) -> Bool {
    annotation.value(forAnnotationKey: PDFAnnotationKey(rawValue: ownershipKey)) as? Bool == true
  }

  static func tagAsModuleManaged(_ annotation: PDFAnnotation, id: String, createdAt: Double, colorHex: String? = nil) {
    annotation.setValue(true, forAnnotationKey: PDFAnnotationKey(rawValue: ownershipKey))
    annotation.setValue(id, forAnnotationKey: PDFAnnotationKey(rawValue: "_id"))
    annotation.setValue(createdAt, forAnnotationKey: PDFAnnotationKey(rawValue: "_createdAt"))
    if let colorHex {
      annotation.setValue(colorHex, forAnnotationKey: PDFAnnotationKey(rawValue: "_color"))
    }
  }

  // MARK: - Color helpers

  static func colorFromHex(_ hex: String) -> UIColor? {
    var hexStr = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if hexStr.hasPrefix("#") {
      hexStr.removeFirst()
    }
    guard hexStr.count == 6 || hexStr.count == 8 else { return nil }
    guard hexStr.allSatisfy(\.isHexDigit) else { return nil }

    var rgb: UInt64 = 0
    Scanner(string: hexStr).scanHexInt64(&rgb)

    if hexStr.count == 8 {
      return UIColor(
        red: CGFloat((rgb >> 24) & 0xFF) / 255.0,
        green: CGFloat((rgb >> 16) & 0xFF) / 255.0,
        blue: CGFloat((rgb >> 8) & 0xFF) / 255.0,
        alpha: CGFloat(rgb & 0xFF) / 255.0
      )
    }
    return UIColor(
      red: CGFloat((rgb >> 16) & 0xFF) / 255.0,
      green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
      blue: CGFloat(rgb & 0xFF) / 255.0,
      alpha: 1.0
    )
  }

  static func hexFromColor(_ color: UIColor) -> String {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    return String(
      format: "#%02X%02X%02X",
      Int(round(red * 255)),
      Int(round(green * 255)),
      Int(round(blue * 255))
    )
  }

  // MARK: - Private helpers

  private static func createInkAnnotation(
    model: AnnotationModel,
    color: UIColor,
    pageBounds: CGRect? = nil
  ) -> PDFAnnotation {
    let paths = model.decodedPaths
    let lineWidth = model.lineWidth ?? 2.0

    // Use full page bounds if available; otherwise compute from points with generous padding.
    // PDFKit clips ink rendering to the annotation bounds rect, so tight bounds cause
    // strokes to be partially or fully invisible.
    let annotationBounds: CGRect
    if let pageBounds {
      annotationBounds = pageBounds
    } else {
      var combinedRect = CGRect.null
      for path in paths {
        for point in path {
          combinedRect = combinedRect.union(CGRect(x: point.x, y: point.y, width: 0, height: 0))
        }
      }
      let padding = max(lineWidth * 2, 10.0)
      annotationBounds = combinedRect.insetBy(dx: -padding, dy: -padding)
    }

    let annotation = PDFAnnotation(bounds: annotationBounds, forType: .ink, withProperties: nil)
    annotation.color = color

    let border = PDFBorder()
    border.lineWidth = lineWidth
    annotation.border = border

    for path in paths {
      let bezierPath = UIBezierPath()
      for (index, point) in path.enumerated() {
        if index == 0 {
          bezierPath.move(to: CGPoint(x: point.x - annotationBounds.minX, y: point.y - annotationBounds.minY))
        } else {
          bezierPath.addLine(to: CGPoint(x: point.x - annotationBounds.minX, y: point.y - annotationBounds.minY))
        }
      }
      annotation.add(bezierPath)
    }

    let createdAt = model.createdAt ?? Date().timeIntervalSince1970
    tagAsModuleManaged(annotation, id: model.id, createdAt: createdAt, colorHex: model.color)
    return annotation
  }

  private static func createMarkupAnnotation(
    model: AnnotationModel,
    color: UIColor,
    subtype: PDFAnnotationSubtype
  ) -> PDFAnnotation? {
    guard let bounds = model.bounds else { return nil }
    let annotation = PDFAnnotation(bounds: bounds.cgRect, forType: subtype, withProperties: nil)
    let alpha = model.alpha ?? (subtype == .highlight ? 0.5 : 1.0)
    annotation.color = color.withAlphaComponent(alpha)

    let createdAt = model.createdAt ?? Date().timeIntervalSince1970
    tagAsModuleManaged(annotation, id: model.id, createdAt: createdAt, colorHex: model.color)
    return annotation
  }

  private static func createFreeTextAnnotation(model: AnnotationModel, color: UIColor) -> PDFAnnotation? {
    guard let bounds = model.bounds else { return nil }
    let fontSize = model.fontSize ?? 16.0
    let font = UIFont(name: model.fontFamily ?? "", size: fontSize) ?? UIFont.systemFont(ofSize: fontSize)
    let contents = model.contents ?? ""
    let annotation = PDFAnnotation(
      bounds: bounds.cgRect,
      forType: .freeText,
      withProperties: nil
    )
    annotation.font = font
    annotation.fontColor = color
    annotation.color = .clear
    annotation.contents = contents
    annotation.setValue(model.type, forAnnotationKey: PDFAnnotationKey(rawValue: "_modelType"))

    let createdAt = model.createdAt ?? Date().timeIntervalSince1970
    tagAsModuleManaged(annotation, id: model.id, createdAt: createdAt, colorHex: model.color)
    return annotation
  }

  private static func createStampAnnotation(model: AnnotationModel) -> PDFAnnotation? {
    guard let bounds = model.bounds, let text = model.text else { return nil }

    let annotation = StampPDFAnnotation(bounds: bounds.cgRect, forType: .stamp, withProperties: nil)
    annotation.setStampText(text)

    let createdAt = model.createdAt ?? Date().timeIntervalSince1970
    tagAsModuleManaged(annotation, id: model.id, createdAt: createdAt, colorHex: model.color)
    return annotation
  }

  private static func normalizedFreeTextBounds(bounds: CGRect, text: String, font: UIFont) -> CGRect {
    guard !text.isEmpty else { return bounds }

    let padding: CGFloat = 4.0
    let textSize = (text as NSString).size(withAttributes: [.font: font])
    let width = max(bounds.width, ceil(textSize.width + padding * 2))
    let height = max(bounds.height, ceil(textSize.height + padding * 2))

    return CGRect(
      x: bounds.minX,
      y: bounds.maxY - height,
      width: width,
      height: height
    )
  }

  private static func pointsFromBezierPath(_ path: UIBezierPath) -> [CGPoint] {
    var points: [CGPoint] = []
    let cgPath = path.cgPath
    cgPath.applyWithBlock { element in
      switch element.pointee.type {
      case .moveToPoint, .addLineToPoint:
        points.append(element.pointee.points[0])
      case .addQuadCurveToPoint:
        points.append(element.pointee.points[1])
      case .addCurveToPoint:
        points.append(element.pointee.points[2])
      case .closeSubpath:
        break
      @unknown default:
        break
      }
    }
    return points
  }
}

/// Interchange coordinates are zero-origin, y-up points on the visible, rotated page.
/// PDFKit uses unrotated page coordinates; ink paths additionally use annotation-local points.
struct AnnotationCoordinates {
  let nativeToVisible: CGAffineTransform
  var visibleToNative: CGAffineTransform {
    nativeToVisible.inverted()
  }

  let visibleBounds: CGRect

  init(page: PDFPage) {
    self.init(bounds: page.bounds(for: .cropBox), rotation: page.rotation)
  }

  init(bounds: CGRect, rotation: Int = 0) {
    switch (rotation % 360 + 360) % 360 {
    case 90:
      nativeToVisible = CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: -bounds.minY, ty: bounds.maxX)
      visibleBounds = CGRect(x: 0, y: 0, width: bounds.height, height: bounds.width)
    case 180:
      nativeToVisible = CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: bounds.maxX, ty: bounds.maxY)
      visibleBounds = CGRect(origin: .zero, size: bounds.size)
    case 270:
      nativeToVisible = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: bounds.maxY, ty: -bounds.minX)
      visibleBounds = CGRect(x: 0, y: 0, width: bounds.height, height: bounds.width)
    default:
      nativeToVisible = CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY)
      visibleBounds = CGRect(origin: .zero, size: bounds.size)
    }
  }

  func transform(_ model: AnnotationModel, using transform: CGAffineTransform) -> AnnotationModel {
    var result = model
    if let bounds = model.bounds { result.bounds = AnnotationBounds(bounds.cgRect.applying(transform)) }
    if model.paths != nil {
      result.paths = model.encodedPaths(from: model.decodedPaths.map { stroke in
        stroke.map { point in
          let converted = CGPoint(x: point.x, y: point.y).applying(transform)
          return AnnotationPoint(x: converted.x, y: converted.y)
        }
      })
    }
    return result
  }
}
