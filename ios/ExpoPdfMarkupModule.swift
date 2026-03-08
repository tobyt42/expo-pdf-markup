import ExpoModulesCore

public class ExpoPdfMarkupModule: Module {
  public func definition() -> ModuleDefinition {
    Name("ExpoPdfMarkup")

    View(ExpoPdfMarkupView.self) {
      Prop("source") { (view: ExpoPdfMarkupView, source: String) in
        view.loadPdf(from: source)
      }

      Prop("page") { (view: ExpoPdfMarkupView, page: Int) in
        view.goToPage(page)
      }

      Prop("backgroundColor") { (view: ExpoPdfMarkupView, color: UIColor?) in
        view.setBackgroundColor(color)
      }

      Prop("annotations") { (view: ExpoPdfMarkupView, json: String?) in
        view.loadAnnotations(from: json)
      }

      Prop("annotationMode") { (view: ExpoPdfMarkupView, mode: String?) in
        view.setAnnotationMode(mode ?? "none")
      }

      Prop("annotationColor") { (view: ExpoPdfMarkupView, color: String?) in
        view.annotationColor = color ?? "#FF0000"
      }

      Prop("annotationLineWidth") { (view: ExpoPdfMarkupView, width: Double?) in
        view.annotationLineWidth = CGFloat(width ?? 2.0)
      }

      Events("onPageChanged", "onLoadComplete", "onError", "onAnnotationsChanged")
    }
  }
}
