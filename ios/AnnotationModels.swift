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
    var payload: [String: Any] = [
      "mode": annotation == nil ? "create" : "edit",
      "page": pageIndex,
      "point": [
        "x": point.x,
        "y": point.y,
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
      updateFreeTextAnnotation(annotation, text: text)
    } else {
      addFreeTextAnnotation(text: text, at: point, on: page)
    }
  }

  private func addFreeTextAnnotation(text: String, at point: CGPoint, on page: PDFPage) {
    let fontSize: CGFloat = 16.0
    let font = UIFont(name: annotationFontFamily ?? "", size: fontSize) ?? UIFont.systemFont(ofSize: fontSize)
    let color = AnnotationSerializer.colorFromHex(annotationColor) ?? .red
    let bounds = measuredTextBounds(text: text, font: font, at: point)

    let annotation = PDFAnnotation(bounds: bounds, forType: .freeText, withProperties: nil)
    annotation.font = font
    annotation.fontColor = color
    annotation.color = .clear
    annotation.contents = text

    let id = UUID().uuidString
    AnnotationSerializer.tagAsModuleManaged(annotation, id: id, createdAt: Date().timeIntervalSince1970)
    page.addAnnotation(annotation)
    emitAnnotationsChanged()
  }

  private func updateFreeTextAnnotation(_ annotation: PDFAnnotation, text: String) {
    let fontSize = annotation.font?.pointSize ?? 16.0
    let font = annotation.font ??
      UIFont(name: annotationFontFamily ?? "", size: fontSize) ??
      UIFont.systemFont(ofSize: fontSize)
    let bounds = measuredTextBounds(text: text, font: font, replacing: annotation.bounds)

    annotation.font = font
    annotation.bounds = bounds
    annotation.contents = text
    annotation.color = .clear
    if annotation.fontColor == nil {
      annotation.fontColor = AnnotationSerializer.colorFromHex(annotationColor) ?? .red
    }

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
    (text as NSString).size(withAttributes: [.font: font])
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
