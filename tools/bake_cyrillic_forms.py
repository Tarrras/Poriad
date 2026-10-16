#!/usr/bin/env python3
# Як зібрано шрифти «Корінця» (iosApp/Poruch/Fonts, androidApp/src/main/res/font) з Google Fonts ofl/sofiasans*condensed:
#   fonttools varLib.instancer SofiaSansCondensed[wght].ttf wght=700 --update-name-table -o SofiaSansCondensed-Bold.ttf
#   (так само wght=800 для ExtraBold і SofiaSansExtraCondensed[wght].ttf wght=800), потім цей скрипт на кожен файл.
# Потрібен fonttools: python3 -m pip install fonttools
"""Вшиває стандартні (не болгарські) форми кирилиці Sofia Sans у cmap: шрифт вмикає їх лише через locl для RUS,
а iOS і Android мову тексту шрифту не передають, тож українська отримувала болгарські «g»-подібні д, л, п."""
import sys
from fontTools.ttLib import TTFont
for path in sys.argv[1:]:
    font = TTFont(path)
    gsub = font['GSUB'].table
    lookups = set()
    for record in gsub.ScriptList.ScriptRecord:
        if record.ScriptTag != 'cyrl':
            continue
        for lang in record.Script.LangSysRecord:
            if lang.LangSysTag.strip() == 'RUS':
                for index in lang.LangSys.FeatureIndex:
                    feature = gsub.FeatureList.FeatureRecord[index]
                    if feature.FeatureTag == 'locl':
                        lookups.update(feature.Feature.LookupListIndex)
    mapping = {}
    for index in lookups:
        for sub in gsub.LookupList.Lookup[index].SubTable:
            mapping.update(getattr(sub, 'mapping', {}) or {})
    changed = 0
    for table in font['cmap'].tables:
        if not table.isUnicode():
            continue
        for code, glyph in list(table.cmap.items()):
            if glyph in mapping:
                table.cmap[code] = mapping[glyph]
                changed += 1
    font.save(path)
    print(path, 'remapped', changed, 'of', len(mapping))
