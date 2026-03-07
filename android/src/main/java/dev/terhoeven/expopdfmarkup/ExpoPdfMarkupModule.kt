package dev.terhoeven.expopdfmarkup

import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition

class ExpoPdfMarkupModule : Module() {
    override fun definition() = ModuleDefinition {
        Name("ExpoPdfMarkup")

        View(ExpoPdfMarkupView::class) {
            Prop("source") { view: ExpoPdfMarkupView, source: String ->
                view.loadPdf(source)
            }

            Prop("page") { view: ExpoPdfMarkupView, page: Int ->
                view.goToPage(page)
            }

            Events("onPageChanged", "onLoadComplete", "onError")
        }
    }
}
