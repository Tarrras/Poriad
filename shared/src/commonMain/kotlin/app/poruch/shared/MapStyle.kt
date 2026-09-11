package app.poruch.shared

/**
 * The colours a map style borrows from the platform design system. Both apps hold the same palette
 * in their own token file, so the map takes the ground, the paper and the ink from there and only
 * the hues a city needs — water, greenery, rails — are decided here, where the style lives.
 */
data class MapTokens(
    val canvas: String,
    val canvasTint: String,
    val surface: String,
    val surfaceMuted: String,
    val hairline: String,
    val ink: String,
    val inkSecondary: String,
    val inkTertiary: String,
    val dark: Boolean
)

/**
 * Where the geometry and the letterforms come from. A build config may point them elsewhere; these
 * are the defaults, and they are plain `val`s so the iOS side can read them off the object too.
 * Credit for the data rides along in the tile server's TileJSON, which is what the attribution
 * control on both platforms displays.
 */
object MapEndpoints {
    val TILES = "https://tiles.openfreemap.org/planet"
    val GLYPHS = "https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf"
}

/**
 * «Поруч» draws its own map rather than loading a ready-made one: a hosted style brings its own
 * greys, its own POI icons and its own label sizes, and none of them belong to this app. Here the
 * ground is the same warm paper the screens are printed on, roads are the card surface, and the
 * only things allowed to shout are the pins the app puts down itself.
 *
 * The schema is OpenMapTiles, so the layer and field names match any tile server that serves it.
 */
fun poruchMapStyle(
    tokens: MapTokens,
    tilesUrl: String = MapEndpoints.TILES,
    glyphsUrl: String = MapEndpoints.GLYPHS
): String {
    val c = mapColors(tokens)
    return """
    {
      "version": 8,
      "name": "Poruch ${if (tokens.dark) "Night" else "Paper"}",
      "sources": { "openmaptiles": { "type": "vector", "url": "$tilesUrl" } },
      "glyphs": "$glyphsUrl",
      "layers": [
        ${background(c)},
        ${residential(c)},
        ${greenery(c)},
        ${water(c)},
        ${waterway(c)},
        ${buildings(c)},
        ${roadMinor(c)},
        ${roadMajorCasing(c)},
        ${roadMajor(c)},
        ${motorwayCasing(c)},
        ${motorway(c)},
        ${rail(c)},
        ${boundary(c)},
        ${roadLabels(c)},
        ${waterLabels(c)},
        ${districtLabels(c)},
        ${settlementLabels(c)},
        ${cityLabels(c)}
      ]
    }
    """.trimIndent()
}

/**
 * Map-only hues. Water and greenery have no counterpart in the app's palette — nothing else in
 * «Поруч» is a river — so they are chosen here against the paper rather than invented per platform.
 */
private class MapColors(
    val land: String, val landTint: String, val green: String, val water: String, val waterLine: String,
    val building: String, val buildingLine: String, val roadFill: String, val roadCasing: String,
    val roadMinor: String, val rail: String, val boundary: String,
    val label: String, val labelMuted: String, val labelFaint: String, val labelHalo: String, val waterLabel: String
)

private fun mapColors(t: MapTokens) = if (t.dark) MapColors(
    land = t.canvas, landTint = t.canvasTint, green = "#18211A", water = "#131C21", waterLine = "#1D272C",
    building = t.canvasTint, buildingLine = t.hairline, roadFill = t.surfaceMuted, roadCasing = t.canvasTint,
    roadMinor = t.surface, rail = t.hairline, boundary = t.inkTertiary,
    label = t.ink, labelMuted = t.inkSecondary, labelFaint = t.inkTertiary, labelHalo = t.canvas, waterLabel = "#6E8794"
) else MapColors(
    land = t.canvas, landTint = t.canvasTint, green = "#E3EBDD", water = "#CBD9DE", waterLine = "#B5C7CE",
    building = t.canvasTint, buildingLine = t.hairline, roadFill = t.surface, roadCasing = t.hairline,
    roadMinor = t.surface, rail = "#DCD7C9", boundary = t.inkTertiary,
    label = t.ink, labelMuted = t.inkSecondary, labelFaint = t.inkTertiary, labelHalo = t.canvas, waterLabel = "#6E858F"
)

/** Ukrainian first, then whatever the tile carries — a Kyiv street should not be labelled in English. */
private const val NAME = """["coalesce", ["get", "name:uk"], ["get", "name"]]"""
private const val REGULAR = """["Noto Sans Regular"]"""
private const val BOLD = """["Noto Sans Bold"]"""
private const val ITALIC = """["Noto Sans Italic"]"""
private const val POLYGONS = """["match", ["geometry-type"], ["Polygon", "MultiPolygon"], true, false]"""
private const val LINES = """["match", ["geometry-type"], ["LineString", "MultiLineString"], true, false]"""

private fun zoom(vararg stops: Pair<Number, Number>, base: Double = 1.0) =
    """["interpolate", ["exponential", $base], ["zoom"], ${stops.joinToString(", ") { "${it.first}, ${it.second}" }}]"""

private fun background(c: MapColors) = """
    { "id": "ground", "type": "background", "paint": { "background-color": "${c.land}" } }"""

private fun residential(c: MapColors) = """
    { "id": "residential", "type": "fill", "source": "openmaptiles", "source-layer": "landuse", "maxzoom": 16,
      "filter": ["all", $POLYGONS, ["match", ["get", "class"], ["residential", "suburb", "neighbourhood"], true, false]],
      "paint": { "fill-color": "${c.landTint}", "fill-opacity": ${zoom(8 to 0.4, 13 to 0.75)} } }"""

private fun greenery(c: MapColors) = """
    { "id": "park", "type": "fill", "source": "openmaptiles", "source-layer": "park",
      "filter": $POLYGONS, "paint": { "fill-color": "${c.green}" } },
    { "id": "woodland", "type": "fill", "source": "openmaptiles", "source-layer": "landcover", "minzoom": 8,
      "filter": ["all", $POLYGONS, ["match", ["get", "class"], ["wood", "grass"], true, false]],
      "paint": { "fill-color": "${c.green}", "fill-opacity": ${zoom(8 to 0, 11 to 1)} } }"""

private fun water(c: MapColors) = """
    { "id": "water", "type": "fill", "source": "openmaptiles", "source-layer": "water",
      "filter": ["all", $POLYGONS, ["!=", ["get", "brunnel"], "tunnel"]],
      "paint": { "fill-color": "${c.water}", "fill-antialias": true } }"""

private fun waterway(c: MapColors) = """
    { "id": "waterway", "type": "line", "source": "openmaptiles", "source-layer": "waterway", "minzoom": 8,
      "filter": $LINES,
      "paint": { "line-color": "${c.waterLine}", "line-width": ${zoom(9 to 0.6, 16 to 3.5)} } }"""

/** Blocks appear only once the camera is close enough for a building to mean something. */
private fun buildings(c: MapColors) = """
    { "id": "building", "type": "fill", "source": "openmaptiles", "source-layer": "building", "minzoom": 13,
      "paint": { "fill-color": "${c.building}", "fill-outline-color": "${c.buildingLine}",
                 "fill-opacity": ${zoom(13 to 0, 14.5 to 1)}, "fill-antialias": true } }"""

private fun roadMinor(c: MapColors) = """
    { "id": "road-minor", "type": "line", "source": "openmaptiles", "source-layer": "transportation", "minzoom": 12,
      "filter": ["all", $LINES, ["match", ["get", "class"], ["minor", "service", "track"], true, false]],
      "layout": { "line-cap": "round", "line-join": "round" },
      "paint": { "line-color": "${c.roadMinor}", "line-opacity": ${zoom(12 to 0, 13.5 to 1)},
                 "line-width": ${zoom(13 to 1.4, 20 to 18.0, base = 1.55)} } }"""

private fun roadMajorCasing(c: MapColors) = """
    { "id": "road-major-casing", "type": "line", "source": "openmaptiles", "source-layer": "transportation", "minzoom": 11,
      "filter": ["all", $LINES, ["match", ["get", "class"], ["primary", "secondary", "tertiary", "trunk"], true, false]],
      "layout": { "line-cap": "round", "line-join": "round" },
      "paint": { "line-color": "${c.roadCasing}", "line-width": ${zoom(11 to 3.0, 20 to 24.0, base = 1.3)} } }"""

private fun roadMajor(c: MapColors) = """
    { "id": "road-major", "type": "line", "source": "openmaptiles", "source-layer": "transportation",
      "filter": ["all", $LINES, ["match", ["get", "class"], ["primary", "secondary", "tertiary", "trunk"], true, false]],
      "layout": { "line-cap": "round", "line-join": "round" },
      "paint": { "line-color": "${c.roadFill}", "line-opacity": ${zoom(8 to 0.5, 11 to 1)},
                 "line-width": ${zoom(8 to 0.8, 11 to 2.0, 20 to 20.0, base = 1.3)} } }"""

private fun motorwayCasing(c: MapColors) = """
    { "id": "road-motorway-casing", "type": "line", "source": "openmaptiles", "source-layer": "transportation", "minzoom": 7,
      "filter": ["all", $LINES, ["==", ["get", "class"], "motorway"]],
      "layout": { "line-cap": "round", "line-join": "round" },
      "paint": { "line-color": "${c.roadCasing}", "line-width": ${zoom(7 to 3.0, 20 to 28.0, base = 1.3)} } }"""

private fun motorway(c: MapColors) = """
    { "id": "road-motorway", "type": "line", "source": "openmaptiles", "source-layer": "transportation",
      "filter": ["all", $LINES, ["==", ["get", "class"], "motorway"]],
      "layout": { "line-cap": "round", "line-join": "round" },
      "paint": { "line-color": "${c.roadFill}", "line-width": ${zoom(5 to 0.8, 7 to 1.8, 20 to 24.0, base = 1.3)} } }"""

private fun rail(c: MapColors) = """
    { "id": "rail", "type": "line", "source": "openmaptiles", "source-layer": "transportation", "minzoom": 13,
      "filter": ["all", $LINES, ["==", ["get", "class"], "rail"]],
      "paint": { "line-color": "${c.rail}", "line-width": ${zoom(13 to 0.8, 18 to 2.0)}, "line-dasharray": [3, 2] } }"""

private fun boundary(c: MapColors) = """
    { "id": "boundary", "type": "line", "source": "openmaptiles", "source-layer": "boundary",
      "filter": ["all", ["<=", ["get", "admin_level"], 4], ["!=", ["get", "maritime"], 1]],
      "layout": { "line-cap": "round", "line-join": "round" },
      "paint": { "line-color": "${c.boundary}", "line-opacity": 0.45, "line-dasharray": [4, 3],
                 "line-width": ${zoom(3 to 0.8, 10 to 1.6)} } }"""

/**
 * Street names arrive late, and side streets later still: below a walking zoom a full set of names
 * is a second layer of text competing with the pins the app came to show.
 */
private fun roadLabels(c: MapColors) = """
    { "id": "label-road-major", "type": "symbol", "source": "openmaptiles", "source-layer": "transportation_name", "minzoom": 14,
      "filter": ["match", ["get", "class"], ["motorway", "trunk", "primary", "secondary", "tertiary"], true, false],
      "layout": { "symbol-placement": "line", "text-field": $NAME, "text-font": $REGULAR,
                  "text-size": ${zoom(14 to 10.0, 18 to 12.0)}, "text-letter-spacing": 0.02, "text-rotation-alignment": "map" },
      "paint": { "text-color": "${c.labelFaint}", "text-halo-color": "${c.labelHalo}", "text-halo-width": 1.1 } },
    { "id": "label-road-minor", "type": "symbol", "source": "openmaptiles", "source-layer": "transportation_name", "minzoom": 16,
      "filter": ["match", ["get", "class"], ["minor", "service"], true, false],
      "layout": { "symbol-placement": "line", "text-field": $NAME, "text-font": $REGULAR,
                  "text-size": ${zoom(16 to 10.0, 19 to 11.5)}, "text-letter-spacing": 0.02, "text-rotation-alignment": "map" },
      "paint": { "text-color": "${c.labelFaint}", "text-halo-color": "${c.labelHalo}", "text-halo-width": 1.1 } }"""

/**
 * Rivers and lakes are named only while the whole city is in frame. Higher up the tiles start
 * handing out every fountain in a park, each one class `lake` and none of them a landmark.
 */
private fun waterLabels(c: MapColors) = """
    { "id": "label-water", "type": "symbol", "source": "openmaptiles", "source-layer": "water_name", "minzoom": 8, "maxzoom": 12.5,
      "layout": { "text-field": $NAME, "text-font": $ITALIC, "text-max-width": 6, "text-letter-spacing": 0.1,
                  "text-size": ${zoom(8 to 11.0, 12 to 13.0)} },
      "paint": { "text-color": "${c.waterLabel}", "text-halo-color": "${c.labelHalo}", "text-halo-width": 1.2 } }"""

/**
 * Districts are set the way the app sets a section label — small caps, wide tracking — so the map
 * reads as part of «Поруч» and not as a map with the app drawn on top of it.
 *
 * Only the districts a person would name when arranging to meet: the tiles rank a `suburb` around
 * 15 and a back-yard `neighbourhood` past 40, and printing all of them buries the pins.
 */
private fun districtLabels(c: MapColors) = """
    { "id": "label-district", "type": "symbol", "source": "openmaptiles", "source-layer": "place", "minzoom": 12.5,
      "filter": ["all", ["match", ["get", "class"], ["suburb", "quarter"], true, false], ["<=", ["get", "rank"], 25]],
      "layout": { "text-field": $NAME, "text-font": $BOLD, "text-transform": "uppercase", "text-letter-spacing": 0.14,
                  "text-max-width": 8, "text-size": ${zoom(12.5 to 9.5, 16 to 11.0)} },
      "paint": { "text-color": "${c.labelFaint}", "text-halo-color": "${c.labelHalo}", "text-halo-width": 1.2 } }"""

private fun settlementLabels(c: MapColors) = """
    { "id": "label-settlement", "type": "symbol", "source": "openmaptiles", "source-layer": "place", "minzoom": 8, "maxzoom": 14,
      "filter": ["match", ["get", "class"], ["town", "village", "hamlet"], true, false],
      "layout": { "text-field": $NAME, "text-font": $REGULAR, "text-max-width": 8,
                  "text-size": ${zoom(8 to 11.0, 13 to 13.0)} },
      "paint": { "text-color": "${c.labelMuted}", "text-halo-color": "${c.labelHalo}", "text-halo-width": 1.3 } }"""

/**
 * The city name fades out before the map opens on it: the screen names the city in its own control
 * at the top, and a second headline across the middle only competes with the pins.
 */
private fun cityLabels(c: MapColors) = """
    { "id": "label-city", "type": "symbol", "source": "openmaptiles", "source-layer": "place", "minzoom": 4,
      "filter": ["match", ["get", "class"], ["city", "state", "country"], true, false],
      "layout": { "text-field": $NAME, "text-font": $BOLD, "text-max-width": 8, "text-letter-spacing": -0.01,
                  "text-size": ${zoom(4 to 12.0, 8 to 15.0, 12 to 17.0)} },
      "paint": { "text-color": "${c.label}", "text-opacity": ${zoom(10.5 to 1, 12 to 0)},
                 "text-halo-color": "${c.labelHalo}", "text-halo-width": 1.4 } }"""
