import Foundation
import PDFKit
import UIKit

struct AnnotationPoint: Codable, Equatable {
  let x: CGFloat
  let y: CGFloat
}

struct AnnotationBounds: Codable, Equatable {
  let x: CGFloat
  let y: CGFloat
  let width: CGFloat
  let height: CGFloat

  var cgRect: CGRect {
    CGRect(x: x, y: y, width: width, height: height)
  }

  init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }

  init(_ rect: CGRect) {
    x = rect.origin.x
    y = rect.origin.y
    width = rect.size.width
    height = rect.size.height
  }
}

struct AnnotationModel: Codable, Equatable {
  let id: String
  let type: String
  let page: Int
  let color: String
  var lineWidth: CGFloat?
  var alpha: CGFloat?
  var paths: [[[String: CGFloat]]]?
  var bounds: AnnotationBounds?
  var contents: String?
  var fontSize: CGFloat?
  var fontFamily: String?
  var createdAt: Double?
  var text: String?

  enum CodingKeys: String, CodingKey {
    case id, type, page, color, lineWidth, alpha, paths, bounds, contents, fontSize, fontFamily, createdAt, text
  }

  var decodedPaths: [[AnnotationPoint]] {
    guard let paths else { return [] }
    return paths.map { path in
      path.compactMap { dict in
        guard let x = dict["x"], let y = dict["y"] else { return nil }
        return AnnotationPoint(x: x, y: y)
      }
    }
  }

  func encodedPaths(from points: [[AnnotationPoint]]) -> [[[String: CGFloat]]] {
    points.map { path in
      path.map { point in
        ["x": point.x, "y": point.y]
      }
    }
  }
}

extension AnnotationModel {
  /// Decodes `paths` one ink stroke and one ink point at a time, so an array-form point
  /// (`[x, y]`), a malformed point or a stroke that isn't an array never rejects the whole
  /// annotation set: malformed strokes and points are skipped.
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    type = try container.decode(String.self, forKey: .type)
    page = try container.decode(Int.self, forKey: .page)
    color = try container.decode(String.self, forKey: .color)
    lineWidth = try container.decodeIfPresent(CGFloat.self, forKey: .lineWidth)
    alpha = try container.decodeIfPresent(CGFloat.self, forKey: .alpha)
    paths = try container.decodeIfPresent([InkStrokeReader].self, forKey: .paths)?
      .compactMap(\.points)
    bounds = try container.decodeIfPresent(AnnotationBounds.self, forKey: .bounds)
    contents = try container.decodeIfPresent(String.self, forKey: .contents)
    fontSize = try container.decodeIfPresent(CGFloat.self, forKey: .fontSize)
    fontFamily = try container.decodeIfPresent(String.self, forKey: .fontFamily)
    createdAt = try container.decodeIfPresent(Double.self, forKey: .createdAt)
    text = try container.decodeIfPresent(String.self, forKey: .text)
  }
}

extension AnnotationModel {
  /// Writes every field as the synthesised encoder did, except that an ink annotation's points
  /// are cleaned up and follow the ink point format (see `InkPointCleanup`). Paths on any other
  /// type are written exactly as before. The model itself keeps full precision.
  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(type, forKey: .type)
    try container.encode(page, forKey: .page)
    try container.encode(color, forKey: .color)
    try container.encodeIfPresent(lineWidth, forKey: .lineWidth)
    try container.encodeIfPresent(alpha, forKey: .alpha)
    if type == "ink", paths != nil {
      try container.encode(InkPointCleanup.cleanedPaths(decodedPaths), forKey: .paths)
    } else {
      try container.encodeIfPresent(paths, forKey: .paths)
    }
    try container.encodeIfPresent(bounds, forKey: .bounds)
    try container.encodeIfPresent(contents, forKey: .contents)
    try container.encodeIfPresent(fontSize, forKey: .fontSize)
    try container.encodeIfPresent(fontFamily, forKey: .fontFamily)
    try container.encodeIfPresent(createdAt, forKey: .createdAt)
    try container.encodeIfPresent(text, forKey: .text)
  }
}

/// How ink points are written: object form `{"x": …, "y": …}` (the default) or array form `[x, y]`.
enum InkPointFormat: String {
  case object
  case array

  static let userInfoKey = CodingUserInfoKey(rawValue: "inkPointFormat")!

  /// Maps the `inkPointFormat` view prop; anything other than `"array"` is object form.
  init(prop: String?) {
    self = prop == "array" ? .array : .object
  }
}

/// Ink point clean-up applied only when an annotation set is written (same rule on every
/// platform): each coordinate is rounded to 0.1 pt (the double `value * 10` rounded to the
/// nearest integer, ties away from zero), consecutive duplicates within a stroke are dropped,
/// and a stroke of 2+ points that collapses to one point is written as that point twice.
enum InkPointCleanup {
  /// A rounded coordinate held as the integer number of tenths, so it is written from the
  /// integer (`307.7`, `100`, `-1.3`, never `.0`, `-0` or long trailing digits).
  struct Coordinate: Encodable, Equatable {
    let tenths: Int

    init(_ value: CGFloat) {
      let rounded = Int((Double(value) * 10).rounded())
      tenths = rounded == 0 ? 0 : rounded
    }

    func encode(to encoder: Encoder) throws {
      var container = encoder.singleValueContainer()
      if tenths % 10 == 0 {
        try container.encode(tenths / 10)
      } else {
        // Decimal is written from its exact digits, unlike Double which JSONSerialization
        // may print with long trailing digits.
        try container.encode(Decimal(sign: tenths < 0 ? .minus : .plus, exponent: -1,
                                     significand: Decimal(abs(tenths))))
      }
    }
  }

  struct Point: Encodable, Equatable {
    let x: Coordinate
    let y: Coordinate

    /// Object form (`{"x": …, "y": …}`) unless the encoder asks for array form (`[x, y]`).
    func encode(to encoder: Encoder) throws {
      if encoder.userInfo[InkPointFormat.userInfoKey] as? InkPointFormat == .array {
        var container = encoder.unkeyedContainer()
        try container.encode(x)
        try container.encode(y)
      } else {
        var container = encoder.container(keyedBy: InkPointKeys.self)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
      }
    }
  }

  static func cleanedPaths(_ paths: [[AnnotationPoint]]) -> [[Point]] {
    paths.map(cleanedStroke)
  }

  static func cleanedStroke(_ stroke: [AnnotationPoint]) -> [Point] {
    var kept: [Point] = []
    for point in stroke {
      let rounded = Point(x: Coordinate(point.x), y: Coordinate(point.y))
      if rounded != kept.last { kept.append(rounded) }
    }
    if stroke.count >= 2, kept.count == 1 { kept.append(kept[0]) }
    return kept
  }
}

/// The keys of an ink point in object form.
private enum InkPointKeys: String, CodingKey { case x, y }

/// Reads one ink stroke; anything that isn't an array decodes to nil `points` instead of throwing.
private struct InkStrokeReader: Decodable {
  let points: [[String: CGFloat]]?

  init(from decoder: Decoder) {
    points = (try? [InkPointReader](from: decoder))?.compactMap(\.point)
  }
}

/// Reads one ink point in object form (`{"x": …, "y": …}`) or array form (`[x, y]`), straight
/// into the model's object-form dictionary. Anything else decodes to a nil `point` instead of throwing.
private struct InkPointReader: Decodable {
  let point: [String: CGFloat]?

  init(from decoder: Decoder) {
    if let object = try? decoder.container(keyedBy: InkPointKeys.self),
       let x = try? object.decode(CGFloat.self, forKey: .x),
       let y = try? object.decode(CGFloat.self, forKey: .y) {
      point = ["x": x, "y": y]
    } else if var array = try? decoder.unkeyedContainer(), array.count == 2,
              let x = try? array.decode(CGFloat.self),
              let y = try? array.decode(CGFloat.self) {
      point = ["x": x, "y": y]
    } else {
      point = nil
    }
  }
}

struct AnnotationsData: Codable, Equatable {
  let version: Int
  let annotations: [AnnotationModel]

  init(version: Int = 1, annotations: [AnnotationModel] = []) {
    self.version = version
    self.annotations = annotations
  }
}

extension ExpoPdfMarkupView {
  func setupTextGesture() {
    guard textTapGesture == nil else { return }
    let tap = UITapGestureRecognizer(target: self, action: #selector(handleTextTap(_:)))
    tap.delegate = self
    pdfView.addGestureRecognizer(tap)
    textTapGesture = tap
  }

  func removeTextGesture() {
    if let gesture = textTapGesture {
      pdfView.removeGestureRecognizer(gesture)
      textTapGesture = nil
    }
  }

  @objc func handleTextTap(_ gesture: UITapGestureRecognizer) {
    let location = gesture.location(in: pdfView)
    guard let page = pdfView.page(for: location, nearest: true) else { return }

    let pdfPoint = pdfView.convert(location, to: page)
    let existingAnnotation = editableTextAnnotation(at: pdfPoint, on: page)

    if useJsTextDialog {
      pendingTextPage = page
      pendingTextPoint = pdfPoint
      pendingTextAnnotation = existingAnnotation
      onTextInputRequested(textInputRequestPayload(page: page, point: pdfPoint, annotation: existingAnnotation))
      return
    }

    presentTextAlert(for: page, at: pdfPoint, existingAnnotation: existingAnnotation)
  }

  func provideTextInput(text: String?) {
    guard let page = pendingTextPage, let point = pendingTextPoint else { return }
    let annotation = pendingTextAnnotation
    pendingTextPage = nil
    pendingTextPoint = nil
    pendingTextAnnotation = nil
    guard let text, !text.isEmpty else { return }
    upsertFreeTextAnnotation(text: text, at: point, on: page, replacing: annotation)
  }

  private func presentTextAlert(for page: PDFPage, at point: CGPoint, existingAnnotation: PDFAnnotation?) {
    guard let viewController = findViewController() else { return }
    let isEditing = existingAnnotation != nil
    let alert = UIAlertController(
      title: isEditing ? "Edit Text" : "Add Text",
      message: nil,
      preferredStyle: .alert
    )
    alert.addTextField { textField in
      textField.placeholder = "Enter text"
      textField.text = existingAnnotation?.contents
    }

    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    alert.addAction(UIAlertAction(title: isEditing ? "Update" : "Add", style: .default) { [weak self] _ in
      guard let self, let text = alert.textFields?.first?.text, !text.isEmpty else { return }
      upsertFreeTextAnnotation(text: text, at: point, on: page, replacing: existingAnnotation)
    })

    viewController.present(alert, animated: true)
  }

  private func editableTextAnnotation(at point: CGPoint, on page: PDFPage) -> PDFAnnotation? {
    page.annotations.reversed().first { annotation in
      AnnotationSerializer.isModuleManaged(annotation) &&
        (annotation.type == "FreeText" || annotation.type == "Text") &&
        annotation.bounds.contains(point)
    }
  }

  private func textInputRequestPayload(
    page: PDFPage,
    point: CGPoint,
    annotation: PDFAnnotation?
  ) -> [String: Any] {
    let pageIndex = pdfView.document?.index(for: page) ?? 0
    let visiblePoint = point.applying(AnnotationCoordinates(page: page).nativeToVisible)
    var payload: [String: Any] = [
      "mode": annotation == nil ? "create" : "edit",
      "page": pageIndex,
      "point": [
        "x": visiblePoint.x,
        "y": visiblePoint.y,
      ],
    ]
    if let contents = annotation?.contents {
      payload["currentText"] = contents
    }
    return payload
  }

  private func upsertFreeTextAnnotation(
    text: String,
    at point: CGPoint,
    on page: PDFPage,
    replacing annotation: PDFAnnotation?
  ) {
    if let annotation {
      updateFreeTextAnnotation(annotation, text: text, on: page)
    } else {
      addFreeTextAnnotation(text: text, at: point, on: page)
    }
  }

  private func addFreeTextAnnotation(text: String, at point: CGPoint, on page: PDFPage) {
    let fontSize: CGFloat = 16.0
    let font = UIFont(name: annotationFontFamily ?? "", size: fontSize) ?? UIFont.systemFont(ofSize: fontSize)
    let coordinates = AnnotationCoordinates(page: page)
    let visiblePoint = point.applying(coordinates.nativeToVisible)
    let model = AnnotationModel(
      id: UUID().uuidString, type: "freeText", page: pdfView.document?.index(for: page) ?? 0,
      color: annotationColor,
      bounds: AnnotationBounds(measuredTextBounds(text: text, font: font, at: visiblePoint)),
      contents: text, fontSize: fontSize, fontFamily: font.fontName,
      createdAt: Date().timeIntervalSince1970
    )
    guard let annotation = AnnotationSerializer.toPDFAnnotation(
      model, pageBounds: page.bounds(for: .cropBox), pageRotation: page.rotation
    ) else { return }
    page.addAnnotation(annotation)
    emitAnnotationsChanged()
  }

  private func updateFreeTextAnnotation(_ annotation: PDFAnnotation, text: String, on page: PDFPage) {
    guard var model = AnnotationSerializer.toModel(from: annotation, page: pdfView.document?.index(for: page) ?? 0),
          let bounds = model.bounds else { return }
    let font = annotation.font ?? UIFont.systemFont(ofSize: model.fontSize ?? 16)
    model.contents = text
    model.bounds = AnnotationBounds(measuredTextBounds(text: text, font: font, replacing: bounds.cgRect))
    guard let replacement = AnnotationSerializer.toPDFAnnotation(
      model, pageBounds: page.bounds(for: .cropBox), pageRotation: page.rotation
    ) else { return }
    page.removeAnnotation(annotation)
    page.addAnnotation(replacement)
    emitAnnotationsChanged()
  }

  private func measuredTextBounds(text: String, font: UIFont, at point: CGPoint) -> CGRect {
    let textSize = measuredTextSize(text: text, font: font)
    let padding: CGFloat = 4.0
    return CGRect(
      x: point.x,
      y: point.y - textSize.height - padding,
      width: textSize.width + padding * 2,
      height: textSize.height + padding * 2
    )
  }

  private func measuredTextBounds(text: String, font: UIFont, replacing bounds: CGRect) -> CGRect {
    let textSize = measuredTextSize(text: text, font: font)
    let padding: CGFloat = 4.0
    let height = textSize.height + padding * 2
    return CGRect(
      x: bounds.minX,
      y: bounds.maxY - height,
      width: textSize.width + padding * 2,
      height: height
    )
  }

  private func measuredTextSize(text: String, font: UIFont) -> CGSize {
    let size = (text as NSString).size(withAttributes: [.font: font])
    return CGSize(width: ceil(size.width), height: ceil(size.height))
  }

  private func findViewController() -> UIViewController? {
    var responder: UIResponder? = self
    while let next = responder?.next {
      if let vc = next as? UIViewController {
        return vc
      }
      responder = next
    }
    return nil
  }
}
