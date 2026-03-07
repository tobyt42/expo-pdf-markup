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

      Events("onPageChanged", "onLoadComplete", "onError")
    }
  }
}
