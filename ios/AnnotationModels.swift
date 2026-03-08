import Foundation

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
