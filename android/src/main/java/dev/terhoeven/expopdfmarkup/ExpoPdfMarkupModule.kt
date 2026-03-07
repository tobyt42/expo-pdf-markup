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

            Prop("backgroundColor") { view: ExpoPdfMarkupView, color: String? ->
                view.setPageBackgroundColor(color?.let { android.graphics.Color.parseColor(it) })
            }

            Events("onPageChanged", "onLoadComplete", "onError")
        }
    }
}
