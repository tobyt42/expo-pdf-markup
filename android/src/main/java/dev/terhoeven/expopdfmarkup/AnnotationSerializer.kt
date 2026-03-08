package dev.terhoeven.expopdfmarkup

import org.json.JSONArray
import org.json.JSONObject

object AnnotationSerializer {

    fun deserialize(json: String): AnnotationsData? {
        return try {
            val obj = JSONObject(json)
            val version = obj.optInt("version", 1)
            val arr = obj.optJSONArray("annotations") ?: return AnnotationsData(version)
            val annotations = mutableListOf<AnnotationModel>()
            for (i in 0 until arr.length()) {
                parseAnnotation(arr.getJSONObject(i))?.let { annotations.add(it) }
            }
            AnnotationsData(version, annotations)
        } catch (_: Exception) {
            null
        }
    }

    fun serialize(data: AnnotationsData): String {
        val obj = JSONObject()
        obj.put("version", data.version)
        val arr = JSONArray()
        for (annotation in data.annotations) {
            arr.put(annotationToJson(annotation))
        }
        obj.put("annotations", arr)
        return obj.toString()
    }

    fun colorFromHex(hex: String): Int {
        val cleaned = hex.removePrefix("#")
        return when (cleaned.length) {
            6 -> {
                val rgb = cleaned.toLong(16).toInt()
                (0xFF shl 24) or rgb
            }

            8 -> {
                val r = cleaned.substring(0, 2).toInt(16)
                val g = cleaned.substring(2, 4).toInt(16)
                val b = cleaned.substring(4, 6).toInt(16)
                val a = cleaned.substring(6, 8).toInt(16)
                (a shl 24) or (r shl 16) or (g shl 8) or b
            }

            else -> (0xFF shl 24) // fallback to opaque black
        }
    }

    fun hexFromColor(color: Int): String {
        val r = (color shr 16) and 0xFF
        val g = (color shr 8) and 0xFF
        val b = color and 0xFF
        return "#%02X%02X%02X".format(r, g, b)
    }

    private fun parseAnnotation(obj: JSONObject): AnnotationModel? {
        val id = obj.optString("id", "").ifEmpty { return null }
        val type = obj.optString("type", "").ifEmpty { return null }
        val page = obj.optInt("page", -1)
        if (page < 0) return null
        val color = obj.optString("color", "#000000")

        return AnnotationModel(
            id = id,
            type = type,
            page = page,
            color = color,
            lineWidth = optFloat(obj, "lineWidth"),
            alpha = optFloat(obj, "alpha"),
            paths = parsePaths(obj.optJSONArray("paths")),
            bounds = parseBounds(obj.optJSONObject("bounds")),
            contents = if (obj.has("contents")) obj.getString("contents") else null,
            fontSize = optFloat(obj, "fontSize"),
            createdAt = if (obj.has("createdAt")) obj.optDouble("createdAt") else null
        )
    }

    private fun optFloat(obj: JSONObject, key: String): Float? =
        if (obj.has(key)) obj.optDouble(key).toFloat() else null

    private fun parsePaths(arr: JSONArray?): List<List<AnnotationPoint>>? {
        arr ?: return null
        val paths = mutableListOf<List<AnnotationPoint>>()
        for (i in 0 until arr.length()) {
            val stroke = arr.getJSONArray(i)
            val points = mutableListOf<AnnotationPoint>()
            for (j in 0 until stroke.length()) {
                val pt = stroke.getJSONObject(j)
                points.add(
                    AnnotationPoint(pt.getDouble("x").toFloat(), pt.getDouble("y").toFloat())
                )
            }
            paths.add(points)
        }
        return paths
    }

    private fun parseBounds(obj: JSONObject?): AnnotationBounds? {
        obj ?: return null
        return AnnotationBounds(
            x = obj.getDouble("x").toFloat(),
            y = obj.getDouble("y").toFloat(),
            width = obj.getDouble("width").toFloat(),
            height = obj.getDouble("height").toFloat()
        )
    }

    private fun annotationToJson(model: AnnotationModel): JSONObject {
        val obj = JSONObject()
        obj.put("id", model.id)
        obj.put("type", model.type)
        obj.put("page", model.page)
        obj.put("color", model.color)
        model.lineWidth?.let { obj.put("lineWidth", it.toDouble()) }
        model.alpha?.let { obj.put("alpha", it.toDouble()) }
        model.paths?.let { obj.put("paths", pathsToJson(it)) }
        model.bounds?.let { obj.put("bounds", boundsToJson(it)) }
        model.contents?.let { obj.put("contents", it) }
        model.fontSize?.let { obj.put("fontSize", it.toDouble()) }
        model.createdAt?.let { obj.put("createdAt", it) }
        return obj
    }

    private fun pathsToJson(paths: List<List<AnnotationPoint>>): JSONArray {
        val arr = JSONArray()
        for (stroke in paths) {
            val strokeArr = JSONArray()
            for (pt in stroke) {
                val ptObj = JSONObject()
                ptObj.put("x", pt.x.toDouble())
                ptObj.put("y", pt.y.toDouble())
                strokeArr.put(ptObj)
            }
            arr.put(strokeArr)
        }
        return arr
    }

    private fun boundsToJson(bounds: AnnotationBounds): JSONObject {
        val obj = JSONObject()
        obj.put("x", bounds.x.toDouble())
        obj.put("y", bounds.y.toDouble())
        obj.put("width", bounds.width.toDouble())
        obj.put("height", bounds.height.toDouble())
        return obj
    }
}
