package dev.terhoeven.expopdfmarkup

import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition

// android.graphics.Color.parseColor does not support "transparent" or CSS color functions.
// This helper handles those cases and returns null for unrecognised values (falls back to default).
internal fun parseColorString(color: String): Int? {
    val trimmed = color.trim()

    if (trimmed.equals("transparent", ignoreCase = true)) {
        return android.graphics.Color.TRANSPARENT
    }

    // Handle rgb(r, g, b) and rgba(r, g, b, a)
    val rgbMatch = Regex(
        """^rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)(?:\s*,\s*([\d.]+))?\s*\)$""",
        RegexOption.IGNORE_CASE
    ).matchEntire(trimmed)
    if (rgbMatch != null) {
        val r = rgbMatch.groupValues[1].toIntOrNull()?.coerceIn(0, 255) ?: return null
        val g = rgbMatch.groupValues[2].toIntOrNull()?.coerceIn(0, 255) ?: return null
        val b = rgbMatch.groupValues[3].toIntOrNull()?.coerceIn(0, 255) ?: return null
        val aStr = rgbMatch.groupValues[4]
        val a = if (aStr.isEmpty()) {
            255
        } else {
            (
                (aStr.toFloatOrNull() ?: 1f).coerceIn(
                    0f,
                    1f
                ) * 255
                ).toInt()
        }
        return (a shl 24) or (r shl 16) or (g shl 8) or b
    }

    return try {
        android.graphics.Color.parseColor(trimmed)
    } catch (_: IllegalArgumentException) {
        null
    }
}

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
                view.setPageBackgroundColor(color?.let { parseColorString(it) })
            }

            Events("onPageChanged", "onLoadComplete", "onError")
        }
    }
}
