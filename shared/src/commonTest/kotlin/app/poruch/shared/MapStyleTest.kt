package app.poruch.shared

import kotlinx.serialization.json.*
import kotlin.test.*

/**
 * The style is assembled as text, so the thing worth guarding is that it is still a style: valid
 * JSON, one source, unique layers, and every layer drawn from a source the style declares. A typo
 * inside a paint expression otherwise reaches the device as a blank map.
 */
class MapStyleTest {
    private val tokens = MapTokens(
        canvas = "#F2F0EA", canvasTint = "#EAE6DA", surface = "#FFFFFF", surfaceMuted = "#EDEBE4",
        hairline = "#E5E1D6", ink = "#14130F", inkSecondary = "#6B675E", inkTertiary = "#9A958A", dark = false
    )

    private fun style(dark: Boolean) =
        Json.parseToJsonElement(poruchMapStyle(tokens.copy(dark = dark))).jsonObject

    @Test fun bothSchemesParse() {
        listOf(false, true).forEach { dark ->
            val style = style(dark)
            assertEquals(8, style.getValue("version").jsonPrimitive.int)
            assertTrue(style.getValue("layers").jsonArray.size > 10, "the map needs more than a background")
        }
    }

    @Test fun everyLayerHasItsOwnIdAndAKnownSource() {
        val style = style(false)
        val sources = style.getValue("sources").jsonObject.keys
        val ids = mutableSetOf<String>()
        style.getValue("layers").jsonArray.forEach { element ->
            val layer = element.jsonObject
            val id = layer.getValue("id").jsonPrimitive.content
            assertTrue(ids.add(id), "duplicate layer id $id")
            val source = layer["source"]?.jsonPrimitive?.content
            if (layer.getValue("type").jsonPrimitive.content != "background") {
                assertTrue(source in sources, "layer $id draws from unknown source $source")
                assertNotNull(layer["source-layer"], "layer $id has no source-layer")
            }
        }
    }

    /** Labels are Ukrainian first; a hosted style would hand us English or transliteration. */
    @Test fun labelsPreferUkrainian() {
        val labels = style(false).getValue("layers").jsonArray
            .map { it.jsonObject }.filter { it.getValue("type").jsonPrimitive.content == "symbol" }
        assertTrue(labels.isNotEmpty())
        labels.forEach { layer ->
            val field = layer.getValue("layout").jsonObject.getValue("text-field").toString()
            assertTrue(field.contains("name:uk"), "${layer["id"]} does not ask for the Ukrainian name")
        }
    }

    /** The paper comes from the platform's tokens; water and greenery are the style's own call. */
    @Test fun schemesDifferInTheirOwnHues() {
        fun water(dark: Boolean) = style(dark).getValue("layers").jsonArray
            .map { it.jsonObject }.first { it.getValue("id").jsonPrimitive.content == "water" }
            .getValue("paint").jsonObject.getValue("fill-color").jsonPrimitive.content
        assertNotEquals(water(false), water(true))
    }
}
