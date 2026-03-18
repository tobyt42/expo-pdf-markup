import ExpoModulesCore
import PDFKit

public class ExpoPdfMarkupModule: Module {
  public func definition() -> ModuleDefinition {
    Name("ExpoPdfMarkup")

    AsyncFunction("getEmbeddedAnnotations") { (filePath: String) -> String in
      let url: URL? = URL(string: filePath) ?? URL(fileURLWithPath: filePath)
      guard let url, let document = PDFDocument(url: url) else {
        return "{\"version\":1,\"annotations\":[]}"
      }
      let data = AnnotationSerializer.extractAllNativeAnnotations(from: document)
      return AnnotationSerializer.serialize(data) ?? "{\"version\":1,\"annotations\":[]}"
    }

    AsyncFunction("provideTextInput") { (viewTag: Int, text: String?) in
      DispatchQueue.main.async {
        guard let view = self.appContext?.findView(withTag: viewTag, ofType: ExpoPdfMarkupView.self) else { return }
        view.provideTextInput(text: text)
      }
    }

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

      Prop("annotationFontFamily") { (view: ExpoPdfMarkupView, font: String?) in
        view.annotationFontFamily = font
      }

      Prop("useJsTextDialog") { (view: ExpoPdfMarkupView, use: Bool?) in
        view.useJsTextDialog = use ?? false
      }

      Events("onPageChanged", "onLoadComplete", "onError", "onAnnotationsChanged", "onTextInputRequested")
    }
  }
}
