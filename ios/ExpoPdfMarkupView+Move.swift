import PDFKit
import UIKit

extension ExpoPdfMarkupView {
  // MARK: - Move

  func setupMoveMode() {
    guard movePanGesture == nil else { return }
    pdfScrollView?.isScrollEnabled = false
    let pan = UIPanGestureRecognizer(target: self, action: #selector(handleMovePan(_:)))
    pan.maximumNumberOfTouches = 1
    pan.delegate = self
    pdfView.addGestureRecognizer(pan)
    movePanGesture = pan
  }

  func removeMoveMode() {
    if let gesture = movePanGesture {
      pdfView.removeGestureRecognizer(gesture)
      movePanGesture = nil
    }
    finishMove(commit: false)
    pdfScrollView?.isScrollEnabled = true
  }

  @objc func handleMovePan(_ gesture: UIPanGestureRecognizer) {
    switch gesture.state {
    case .began:
      beginMove(at: gesture.location(in: pdfView))
    case .changed:
      updateMove(at: gesture.location(in: pdfView))
    case .ended:
      finishMove(commit: true)
    case .cancelled, .failed:
      finishMove(commit: false)
    default:
      break
    }
  }

  private func beginMove(at location: CGPoint) {
    guard let document = pdfView.document,
          let page = pdfView.page(for: location, nearest: true) else { return }

    let pdfPoint = pdfView.convert(location, to: page)
    guard let annotation = hitTestAnnotation(at: pdfPoint, on: page) else { return }

    let pageIndex = document.index(for: page)
    guard let model = AnnotationSerializer.toModel(from: annotation, page: pageIndex),
          let preview = annotationForModel(model, on: page) else { return }

    movingPage = page
    movingOriginalModel = model
    movingPreviewModel = model
    moveStartPoint = pdfPoint

    page.removeAnnotation(annotation)
    page.addAnnotation(preview)
    movingPreviewAnnotation = preview
    updateEditingOverlay()
  }

  private func updateMove(at location: CGPoint) {
    guard let page = movingPage,
          let originalModel = movingOriginalModel,
          let startPoint = moveStartPoint else { return }

    let pdfPoint = pdfView.convert(location, to: page)
    let rawDeltaX = pdfPoint.x - startPoint.x
    let rawDeltaY = pdfPoint.y - startPoint.y
    let clampedDelta = clampedTranslation(for: originalModel, dx: rawDeltaX, dy: rawDeltaY, on: page)
    let translatedModel = translatedModel(originalModel, dx: clampedDelta.x, dy: clampedDelta.y)
    guard translatedModel != movingPreviewModel,
          let replacement = annotationForModel(translatedModel, on: page) else { return }

    if let currentPreview = movingPreviewAnnotation {
      page.removeAnnotation(currentPreview)
    }
    page.addAnnotation(replacement)
    movingPreviewAnnotation = replacement
    movingPreviewModel = translatedModel
    updateEditingOverlay()
  }

  private func finishMove(commit: Bool) {
    guard let page = movingPage,
          let originalModel = movingOriginalModel else {
      clearMoveState()
      updateEditingOverlay()
      return
    }

    if let preview = movingPreviewAnnotation {
      page.removeAnnotation(preview)
    }

    let finalModel = commit ? (movingPreviewModel ?? originalModel) : originalModel
    if let finalAnnotation = annotationForModel(finalModel, on: page) {
      page.addAnnotation(finalAnnotation)
    }

    let didChange = commit && finalModel != originalModel
    clearMoveState()
    updateEditingOverlay()

    if didChange {
      emitAnnotationsChanged()
    }
  }

  private func clearMoveState() {
    movingPage = nil
    movingOriginalModel = nil
    movingPreviewModel = nil
    movingPreviewAnnotation = nil
    moveStartPoint = nil
  }

  // MARK: - Editing overlay

  func updateEditingOverlay() {
    guard currentMode == "move" || currentMode == "eraser" else {
      editingOverlayLayer?.removeFromSuperlayer()
      editingOverlayLayer = nil
      return
    }

    guard let document = pdfView.document,
          let documentView = pdfView.documentView else { return }

    let overlay = editingOverlayLayer ?? {
      let shape = CAShapeLayer()
      shape.fillColor = UIColor.clear.cgColor
      shape.strokeColor = UIColor.systemBlue.cgColor
      shape.lineWidth = 1.5
      shape.lineDashPattern = [6, 4]
      documentView.layer.addSublayer(shape)
      editingOverlayLayer = shape
      return shape
    }()

    if overlay.superlayer !== documentView.layer {
      overlay.removeFromSuperlayer()
      documentView.layer.addSublayer(overlay)
    }

    overlay.frame = documentView.bounds
    let path = UIBezierPath()

    for pageIndex in 0 ..< document.pageCount {
      guard let page = document.page(at: pageIndex) else { continue }
      for annotation in page.annotations where AnnotationSerializer.isModuleManaged(annotation) {
        guard let outlineRect = annotationOutlineRect(for: annotation, on: page, in: documentView) else {
          continue
        }
        path.append(UIBezierPath(rect: outlineRect))
      }
    }

    overlay.path = path.cgPath
  }

  private func annotationOutlineRect(
    for annotation: PDFAnnotation,
    on page: PDFPage,
    in documentView: UIView
  ) -> CGRect? {
    let pdfRect: CGRect
    if let paths = annotation.paths, !paths.isEmpty {
      var combinedBounds = CGRect.null
      for path in paths {
        combinedBounds = combinedBounds.union(path.cgPath.boundingBoxOfPath)
      }
      guard !combinedBounds.isNull else { return nil }
      let padding = max(annotation.border?.lineWidth ?? 2.0, 10.0)
      pdfRect = combinedBounds.insetBy(dx: -padding, dy: -padding)
    } else {
      pdfRect = annotation.bounds
    }

    let pdfViewRect = pdfView.convert(pdfRect, from: page)
    return documentView.convert(pdfViewRect, from: pdfView)
  }

  private func annotationForModel(_ model: AnnotationModel, on page: PDFPage) -> PDFAnnotation? {
    AnnotationSerializer.toPDFAnnotation(model, pageBounds: page.bounds(for: pdfView.displayBox))
  }

  private func translatedModel(_ model: AnnotationModel, dx: CGFloat, dy: CGFloat) -> AnnotationModel {
    guard dx != 0 || dy != 0 else { return model }

    var updated = model
    switch model.type {
    case "ink":
      let translatedPaths = model.decodedPaths.map { stroke in
        stroke.map { point in
          AnnotationPoint(x: point.x + dx, y: point.y + dy)
        }
      }
      updated.paths = updated.encodedPaths(from: translatedPaths)
    case "highlight", "underline", "text", "freeText":
      if let bounds = model.bounds {
        updated.bounds = AnnotationBounds(
          x: bounds.x + dx,
          y: bounds.y + dy,
          width: bounds.width,
          height: bounds.height
        )
      }
    default:
      break
    }
    return updated
  }

  private func clampedTranslation(
    for model: AnnotationModel,
    dx: CGFloat,
    dy: CGFloat,
    on page: PDFPage
  ) -> CGPoint {
    guard let outlineBounds = annotationOutlineBounds(for: model) else {
      return CGPoint(x: dx, y: dy)
    }

    let pageBounds = page.bounds(for: pdfView.displayBox)
    let minDx = pageBounds.minX - outlineBounds.x
    let maxDx = pageBounds.maxX - (outlineBounds.x + outlineBounds.width)
    let minDy = pageBounds.minY - outlineBounds.y
    let maxDy = pageBounds.maxY - (outlineBounds.y + outlineBounds.height)

    return CGPoint(
      x: min(max(dx, minDx), maxDx),
      y: min(max(dy, minDy), maxDy)
    )
  }

  private func annotationOutlineBounds(for model: AnnotationModel) -> AnnotationBounds? {
    guard model.type == "ink" else { return model.bounds }
    let paths = model.decodedPaths
    var minX = CGFloat.greatestFiniteMagnitude
    var minY = CGFloat.greatestFiniteMagnitude
    var maxX = -CGFloat.greatestFiniteMagnitude
    var maxY = -CGFloat.greatestFiniteMagnitude

    for stroke in paths {
      for point in stroke {
        minX = min(minX, point.x)
        minY = min(minY, point.y)
        maxX = max(maxX, point.x)
        maxY = max(maxY, point.y)
      }
    }

    guard minX.isFinite, minY.isFinite, maxX.isFinite, maxY.isFinite else { return nil }

    let padding = max(model.lineWidth ?? 2.0, 10.0)
    return AnnotationBounds(
      x: minX - padding,
      y: minY - padding,
      width: maxX - minX + padding * 2,
      height: maxY - minY + padding * 2
    )
  }
}
