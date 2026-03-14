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

  static func toPDFAnnotation(_ model: AnnotationModel, pageBounds: CGRect? = nil) -> PDFAnnotation? {
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

    guard let type = modelType(for: annotation.type) else { return nil }
    var model = AnnotationModel(
      id: id,
      type: type,
      page: page,
      color: colorHex(for: annotation, type: type),
      createdAt: createdAt
    )

    populateModelDetails(&model, from: annotation)

    return model
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
      if let bezierPaths = annotation.paths {
        model.paths = bezierPaths.map { path in
          pointsFromBezierPath(path).map { ["x": $0.x, "y": $0.y] }
        }
      }
    case "highlight", "underline":
      model.bounds = AnnotationBounds(annotation.bounds)
      if model.type == "highlight" {
        model.alpha = 0.5
      }
    case "text", "freeText":
      model.bounds = AnnotationBounds(annotation.bounds)
      model.contents = annotation.contents
      if let font = annotation.font {
        model.fontSize = font.pointSize
        model.fontFamily = font.fontName
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
          bezierPath.move(to: CGPoint(x: point.x, y: point.y))
        } else {
          bezierPath.addLine(to: CGPoint(x: point.x, y: point.y))
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
    let annotation = PDFAnnotation(bounds: bounds.cgRect, forType: .freeText, withProperties: nil)
    let fontSize = model.fontSize ?? 16.0
    annotation.font = UIFont(name: model.fontFamily ?? "", size: fontSize) ?? UIFont.systemFont(ofSize: fontSize)
    annotation.fontColor = color
    annotation.color = .clear
    annotation.contents = model.contents ?? ""

    let createdAt = model.createdAt ?? Date().timeIntervalSince1970
    tagAsModuleManaged(annotation, id: model.id, createdAt: createdAt, colorHex: model.color)
    return annotation
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
