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
    case "text":
      return createTextAnnotation(model: model, color: color)
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

    let type: String
    switch annotation.type {
    case "Ink":
      type = "ink"
    case "Highlight":
      type = "highlight"
    case "Underline":
      type = "underline"
    case "Text":
      type = "text"
    default:
      return nil
    }

    let colorHex = hexFromColor(annotation.color ?? .red)
    var model = AnnotationModel(
      id: id,
      type: type,
      page: page,
      color: colorHex,
      createdAt: createdAt
    )

    switch type {
    case "ink":
      model.lineWidth = annotation.border?.lineWidth ?? 2.0
      if let bezierPaths = annotation.paths {
        model.paths = bezierPaths.map { path in
          pointsFromBezierPath(path).map { ["x": $0.x, "y": $0.y] }
        }
      }
    case "highlight", "underline":
      model.bounds = AnnotationBounds(annotation.bounds)
      if type == "highlight" {
        model.alpha = 0.5
      }
    case "text":
      model.bounds = AnnotationBounds(annotation.bounds)
      model.contents = annotation.contents
    default:
      break
    }

    return model
  }

  // MARK: - Ownership

  static func isModuleManaged(_ annotation: PDFAnnotation) -> Bool {
    annotation.value(forAnnotationKey: PDFAnnotationKey(rawValue: ownershipKey)) as? Bool == true
  }

  static func tagAsModuleManaged(_ annotation: PDFAnnotation, id: String, createdAt: Double) {
    annotation.setValue(true, forAnnotationKey: PDFAnnotationKey(rawValue: ownershipKey))
    annotation.setValue(id, forAnnotationKey: PDFAnnotationKey(rawValue: "_id"))
    annotation.setValue(createdAt, forAnnotationKey: PDFAnnotationKey(rawValue: "_createdAt"))
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
    tagAsModuleManaged(annotation, id: model.id, createdAt: createdAt)
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
    tagAsModuleManaged(annotation, id: model.id, createdAt: createdAt)
    return annotation
  }

  private static func createTextAnnotation(model: AnnotationModel, color: UIColor) -> PDFAnnotation? {
    let bounds = model.bounds?.cgRect ?? CGRect(x: 0, y: 0, width: 24, height: 24)
    let annotation = PDFAnnotation(bounds: bounds, forType: .text, withProperties: nil)
    annotation.color = color
    annotation.contents = model.contents ?? "Note"

    let createdAt = model.createdAt ?? Date().timeIntervalSince1970
    tagAsModuleManaged(annotation, id: model.id, createdAt: createdAt)
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
