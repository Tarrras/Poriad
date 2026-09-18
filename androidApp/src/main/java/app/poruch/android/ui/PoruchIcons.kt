package app.poruch.android.ui

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.unit.dp

/**
 * Власні гліфи застосунку: тонка лінія на сітці 24, заливка лише для крапок.
 *
 * ЗГЕНЕРОВАНО tools/generate_icons.py: геометрію правити там, інакше Swift-двійник у
 * DesignSystem/PoruchIcons.swift розійдеться з цим файлом.
 *
 * Усе чорне: `Icon(tint = …)` перефарбовує весь вектор.
 */
object PoruchIcons {
    /** Восьма нота: кільце головки, стебло і прапорець однією кривою. */
    val music: ImageVector by lazy {
        builder("music")
            .stroke {
                moveTo(5.5f, 16.5f)
                curveTo(5.5f, 14.843f, 6.843f, 13.5f, 8.5f, 13.5f)
                curveTo(10.157f, 13.5f, 11.5f, 14.843f, 11.5f, 16.5f)
                curveTo(11.5f, 18.157f, 10.157f, 19.5f, 8.5f, 19.5f)
                curveTo(6.843f, 19.5f, 5.5f, 18.157f, 5.5f, 16.5f)
                close()
                moveTo(11.5f, 16.5f)
                lineTo(11.5f, 4.5f)
                moveTo(11.5f, 4.5f)
                curveTo(14.5f, 5f, 18f, 6.5f, 18f, 10.5f)
            }
            .build()
    }

    /** Вимпел на держаку. М'яч був би третім колом у наборі. */
    val sport: ImageVector by lazy {
        builder("sport")
            .stroke {
                moveTo(6.5f, 3.5f)
                lineTo(6.5f, 20.5f)
                moveTo(6.5f, 4.5f)
                lineTo(18.5f, 8.2f)
                lineTo(6.5f, 11.9f)
                close()
            }
            .build()
    }

    /** Пензель: короткий держак і великий лист щетини. Голова займає пів гліфа, інакше на піні лишається сама риска. */
    val art: ImageVector by lazy {
        builder("art")
            .fill {
                moveTo(8.4f, 15.6f)
                curveTo(8.6f, 10.6f, 13.6f, 5f, 20.6f, 3.4f)
                curveTo(19f, 10.4f, 13.4f, 15.4f, 8.4f, 15.6f)
                close()
            }
            .stroke {
                moveTo(4f, 20f)
                lineTo(9.8f, 14.2f)
            }
            .build()
    }

    /** Миска під двома завитками пари. */
    val food: ImageVector by lazy {
        builder("food")
            .stroke {
                moveTo(9.5f, 8.5f)
                curveTo(9.5f, 7f, 11f, 6.5f, 11f, 4.5f)
                moveTo(14f, 8.5f)
                curveTo(14f, 7f, 15.5f, 6.5f, 15.5f, 4.5f)
                moveTo(4f, 11.5f)
                lineTo(20f, 11.5f)
                moveTo(4.5f, 11.5f)
                curveTo(4.5f, 16.5f, 7.8f, 20f, 12f, 20f)
                curveTo(16.2f, 20f, 19.5f, 16.5f, 19.5f, 11.5f)
            }
            .build()
    }

    /** Гральний кубик контуром із трьома очками по діагоналі. */
    val games: ImageVector by lazy {
        builder("games")
            .fill {
                moveTo(7.25f, 8.6f)
                curveTo(7.25f, 7.854f, 7.854f, 7.25f, 8.6f, 7.25f)
                curveTo(9.346f, 7.25f, 9.95f, 7.854f, 9.95f, 8.6f)
                curveTo(9.95f, 9.346f, 9.346f, 9.95f, 8.6f, 9.95f)
                curveTo(7.854f, 9.95f, 7.25f, 9.346f, 7.25f, 8.6f)
                close()
                moveTo(10.65f, 12f)
                curveTo(10.65f, 11.254f, 11.254f, 10.65f, 12f, 10.65f)
                curveTo(12.746f, 10.65f, 13.35f, 11.254f, 13.35f, 12f)
                curveTo(13.35f, 12.746f, 12.746f, 13.35f, 12f, 13.35f)
                curveTo(11.254f, 13.35f, 10.65f, 12.746f, 10.65f, 12f)
                close()
                moveTo(14.05f, 15.4f)
                curveTo(14.05f, 14.654f, 14.654f, 14.05f, 15.4f, 14.05f)
                curveTo(16.146f, 14.05f, 16.75f, 14.654f, 16.75f, 15.4f)
                curveTo(16.75f, 16.146f, 16.146f, 16.75f, 15.4f, 16.75f)
                curveTo(14.654f, 16.75f, 14.05f, 16.146f, 14.05f, 15.4f)
                close()
            }
            .stroke {
                moveTo(8.1f, 4.5f)
                lineTo(15.9f, 4.5f)
                curveTo(17.888f, 4.5f, 19.5f, 6.112f, 19.5f, 8.1f)
                lineTo(19.5f, 15.9f)
                curveTo(19.5f, 17.888f, 17.888f, 19.5f, 15.9f, 19.5f)
                lineTo(8.1f, 19.5f)
                curveTo(6.112f, 19.5f, 4.5f, 17.888f, 4.5f, 15.9f)
                lineTo(4.5f, 8.1f)
                curveTo(4.5f, 6.112f, 6.112f, 4.5f, 8.1f, 4.5f)
                close()
            }
            .build()
    }

    /** Ялина двома ярусами і стовбур. */
    val outdoors: ImageVector by lazy {
        builder("outdoors")
            .stroke {
                moveTo(12f, 3.5f)
                lineTo(7.5f, 10.8f)
                lineTo(9.6f, 10.8f)
                lineTo(5f, 17.5f)
                lineTo(19f, 17.5f)
                lineTo(14.4f, 10.8f)
                lineTo(16.5f, 10.8f)
                close()
                moveTo(12f, 17.5f)
                lineTo(12f, 20.5f)
            }
            .build()
    }

    /** Дві фігури одна за одною: друга лише контуром за плечем першої. */
    val social: ImageVector by lazy {
        builder("social")
            .stroke {
                moveTo(5.7f, 8f)
                curveTo(5.7f, 6.177f, 7.177f, 4.7f, 9f, 4.7f)
                curveTo(10.823f, 4.7f, 12.3f, 6.177f, 12.3f, 8f)
                curveTo(12.3f, 9.823f, 10.823f, 11.3f, 9f, 11.3f)
                curveTo(7.177f, 11.3f, 5.7f, 9.823f, 5.7f, 8f)
                close()
                moveTo(3.5f, 20f)
                curveTo(3.5f, 15.6f, 6f, 13.3f, 9f, 13.3f)
                curveTo(12f, 13.3f, 14.5f, 15.6f, 14.5f, 20f)
                moveTo(15f, 5.3f)
                curveTo(17f, 5.8f, 18.3f, 7.3f, 18.3f, 9f)
                curveTo(18.3f, 10.2f, 17.8f, 11.1f, 17f, 11.7f)
                moveTo(16.5f, 13.6f)
                curveTo(19f, 14.2f, 20.5f, 16.5f, 20.5f, 20f)
            }
            .build()
    }

    /** Мікрофон: капсула, тримач, стійка. */
    val comedy: ImageVector by lazy {
        builder("comedy")
            .stroke {
                moveTo(12f, 3f)
                lineTo(12f, 3f)
                curveTo(13.381f, 3f, 14.5f, 4.119f, 14.5f, 5.5f)
                lineTo(14.5f, 10.5f)
                curveTo(14.5f, 11.881f, 13.381f, 13f, 12f, 13f)
                lineTo(12f, 13f)
                curveTo(10.619f, 13f, 9.5f, 11.881f, 9.5f, 10.5f)
                lineTo(9.5f, 5.5f)
                curveTo(9.5f, 4.119f, 10.619f, 3f, 12f, 3f)
                close()
                moveTo(6.8f, 10f)
                curveTo(6.8f, 13.2f, 9.1f, 15.5f, 12f, 15.5f)
                curveTo(14.9f, 15.5f, 17.2f, 13.2f, 17.2f, 10f)
                moveTo(12f, 15.5f)
                lineTo(12f, 19.5f)
                moveTo(8.8f, 19.5f)
                lineTo(15.2f, 19.5f)
            }
            .build()
    }

    /** Кулька на нитці з вузликом. */
    val kids: ImageVector by lazy {
        builder("kids")
            .stroke {
                moveTo(6.7f, 8.8f)
                curveTo(6.7f, 5.873f, 9.073f, 3.5f, 12f, 3.5f)
                curveTo(14.927f, 3.5f, 17.3f, 5.873f, 17.3f, 8.8f)
                curveTo(17.3f, 11.727f, 14.927f, 14.1f, 12f, 14.1f)
                curveTo(9.073f, 14.1f, 6.7f, 11.727f, 6.7f, 8.8f)
                close()
                moveTo(12f, 14.1f)
                lineTo(11f, 15.6f)
                lineTo(13f, 15.6f)
                close()
                moveTo(12f, 15.6f)
                curveTo(12f, 17.6f, 13.8f, 18.4f, 13.8f, 20.5f)
            }
            .build()
    }

    /** Брама зі склепінням і прорізом. */
    val tours: ImageVector by lazy {
        builder("tours")
            .stroke {
                moveTo(4f, 20.5f)
                lineTo(4f, 11.5f)
                curveTo(4f, 7.1f, 7.6f, 3.5f, 12f, 3.5f)
                curveTo(16.4f, 3.5f, 20f, 7.1f, 20f, 11.5f)
                lineTo(20f, 20.5f)
                moveTo(8.7f, 20.5f)
                lineTo(8.7f, 12.5f)
                curveTo(8.7f, 10.7f, 10.2f, 9.2f, 12f, 9.2f)
                curveTo(13.8f, 9.2f, 15.3f, 10.7f, 15.3f, 12.5f)
                lineTo(15.3f, 20.5f)
                moveTo(3f, 20.5f)
                lineTo(21f, 20.5f)
            }
            .build()
    }

    /** Слайд на стійці з двома рядками різної довжини. */
    val conference: ImageVector by lazy {
        builder("conference")
            .stroke {
                moveTo(5.9f, 4f)
                lineTo(18.1f, 4f)
                curveTo(19.425f, 4f, 20.5f, 5.075f, 20.5f, 6.4f)
                lineTo(20.5f, 13.6f)
                curveTo(20.5f, 14.925f, 19.425f, 16f, 18.1f, 16f)
                lineTo(5.9f, 16f)
                curveTo(4.575f, 16f, 3.5f, 14.925f, 3.5f, 13.6f)
                lineTo(3.5f, 6.4f)
                curveTo(3.5f, 5.075f, 4.575f, 4f, 5.9f, 4f)
                close()
                moveTo(7.5f, 8.3f)
                lineTo(16.5f, 8.3f)
                moveTo(7.5f, 11.7f)
                lineTo(13f, 11.7f)
                moveTo(12f, 16f)
                lineTo(12f, 19.5f)
                moveTo(8.5f, 19.5f)
                lineTo(15.5f, 19.5f)
            }
            .build()
    }

    /** Дах, стіни й двері трьома лініями. */
    val home: ImageVector by lazy {
        builder("home")
            .stroke {
                moveTo(3.5f, 11.5f)
                lineTo(12f, 4f)
                lineTo(20.5f, 11.5f)
                moveTo(5.7f, 9.6f)
                lineTo(5.7f, 20f)
                lineTo(18.3f, 20f)
                lineTo(18.3f, 9.6f)
                moveTo(10f, 20f)
                lineTo(10f, 14.5f)
                lineTo(14f, 14.5f)
                lineTo(14f, 20f)
            }
            .build()
    }

    /** Складена мапа з двома згинами. */
    val map: ImageVector by lazy {
        builder("map")
            .stroke {
                moveTo(3.5f, 6f)
                lineTo(9f, 4f)
                lineTo(15f, 6.5f)
                lineTo(20.5f, 4.5f)
                lineTo(20.5f, 18f)
                lineTo(15f, 20f)
                lineTo(9f, 17.5f)
                lineTo(3.5f, 19.5f)
                close()
                moveTo(9f, 4f)
                lineTo(9f, 17.5f)
                moveTo(15f, 6.5f)
                lineTo(15f, 20f)
            }
            .build()
    }

    /** Сторінка з шапкою, двома вушками і крапкою сьогоднішнього дня. */
    val calendar: ImageVector by lazy {
        builder("calendar")
            .fill {
                moveTo(10.65f, 15f)
                curveTo(10.65f, 14.254f, 11.254f, 13.65f, 12f, 13.65f)
                curveTo(12.746f, 13.65f, 13.35f, 14.254f, 13.35f, 15f)
                curveTo(13.35f, 15.746f, 12.746f, 16.35f, 12f, 16.35f)
                curveTo(11.254f, 16.35f, 10.65f, 15.746f, 10.65f, 15f)
                close()
            }
            .stroke {
                moveTo(6.5f, 5f)
                lineTo(17.5f, 5f)
                curveTo(19.157f, 5f, 20.5f, 6.343f, 20.5f, 8f)
                lineTo(20.5f, 17.5f)
                curveTo(20.5f, 19.157f, 19.157f, 20.5f, 17.5f, 20.5f)
                lineTo(6.5f, 20.5f)
                curveTo(4.843f, 20.5f, 3.5f, 19.157f, 3.5f, 17.5f)
                lineTo(3.5f, 8f)
                curveTo(3.5f, 6.343f, 4.843f, 5f, 6.5f, 5f)
                close()
                moveTo(3.5f, 10f)
                lineTo(20.5f, 10f)
                moveTo(8f, 3f)
                lineTo(8f, 7f)
                moveTo(16f, 3f)
                lineTo(16f, 7f)
            }
            .build()
    }

    /** Голова й плечі, відкриті знизу, щоб стояти на базовій лінії. */
    val person: ImageVector by lazy {
        builder("person")
            .stroke {
                moveTo(8.2f, 8f)
                curveTo(8.2f, 5.901f, 9.901f, 4.2f, 12f, 4.2f)
                curveTo(14.099f, 4.2f, 15.8f, 5.901f, 15.8f, 8f)
                curveTo(15.8f, 10.099f, 14.099f, 11.8f, 12f, 11.8f)
                curveTo(9.901f, 11.8f, 8.2f, 10.099f, 8.2f, 8f)
                close()
                moveTo(4.5f, 20.5f)
                curveTo(4.5f, 16f, 7.8f, 13.8f, 12f, 13.8f)
                curveTo(16.2f, 13.8f, 19.5f, 16f, 19.5f, 20.5f)
            }
            .build()
    }

    val search: ImageVector by lazy {
        builder("search")
            .stroke {
                moveTo(4f, 10.5f)
                curveTo(4f, 6.91f, 6.91f, 4f, 10.5f, 4f)
                curveTo(14.09f, 4f, 17f, 6.91f, 17f, 10.5f)
                curveTo(17f, 14.09f, 14.09f, 17f, 10.5f, 17f)
                curveTo(6.91f, 17f, 4f, 14.09f, 4f, 10.5f)
                close()
                moveTo(15.3f, 15.3f)
                lineTo(20.5f, 20.5f)
            }
            .build()
    }

    /** Три повзунки: налаштування, а не лійка. */
    val filters: ImageVector by lazy {
        builder("filters")
            .fill {
                moveTo(7.1f, 7f)
                curveTo(7.1f, 5.951f, 7.951f, 5.1f, 9f, 5.1f)
                curveTo(10.049f, 5.1f, 10.9f, 5.951f, 10.9f, 7f)
                curveTo(10.9f, 8.049f, 10.049f, 8.9f, 9f, 8.9f)
                curveTo(7.951f, 8.9f, 7.1f, 8.049f, 7.1f, 7f)
                close()
                moveTo(13.1f, 12f)
                curveTo(13.1f, 10.951f, 13.951f, 10.1f, 15f, 10.1f)
                curveTo(16.049f, 10.1f, 16.9f, 10.951f, 16.9f, 12f)
                curveTo(16.9f, 13.049f, 16.049f, 13.9f, 15f, 13.9f)
                curveTo(13.951f, 13.9f, 13.1f, 13.049f, 13.1f, 12f)
                close()
                moveTo(9.1f, 17f)
                curveTo(9.1f, 15.951f, 9.951f, 15.1f, 11f, 15.1f)
                curveTo(12.049f, 15.1f, 12.9f, 15.951f, 12.9f, 17f)
                curveTo(12.9f, 18.049f, 12.049f, 18.9f, 11f, 18.9f)
                curveTo(9.951f, 18.9f, 9.1f, 18.049f, 9.1f, 17f)
                close()
            }
            .stroke {
                moveTo(4f, 7f)
                lineTo(20f, 7f)
                moveTo(4f, 12f)
                lineTo(20f, 12f)
                moveTo(4f, 17f)
                lineTo(20f, 17f)
            }
            .build()
    }

    val bookmark: ImageVector by lazy {
        builder("bookmark")
            .stroke {
                moveTo(6f, 3.5f)
                lineTo(18f, 3.5f)
                lineTo(18f, 20.5f)
                lineTo(12f, 15.8f)
                lineTo(6f, 20.5f)
                close()
            }
            .build()
    }

    /** Збережено: та сама закладка, залита. */
    val bookmarkFilled: ImageVector by lazy {
        builder("bookmarkFilled")
            .fill {
                moveTo(6f, 3.5f)
                lineTo(18f, 3.5f)
                lineTo(18f, 20.5f)
                lineTo(12f, 15.8f)
                lineTo(6f, 20.5f)
                close()
            }
            .build()
    }

    val plus: ImageVector by lazy {
        builder("plus")
            .stroke {
                moveTo(12f, 5f)
                lineTo(12f, 19f)
                moveTo(5f, 12f)
                lineTo(19f, 12f)
            }
            .build()
    }

    /** Знак застосунку: крапля з кільцем, у гліфі — контуром. */
    val pin: ImageVector by lazy {
        builder("pin")
            .stroke {
                moveTo(12f, 21f)
                curveTo(12f, 21f, 4.8f, 13.6f, 4.8f, 9.4f)
                curveTo(4.8f, 5.4f, 8f, 2.8f, 12f, 2.8f)
                curveTo(16f, 2.8f, 19.2f, 5.4f, 19.2f, 9.4f)
                curveTo(19.2f, 13.6f, 12f, 21f, 12f, 21f)
                close()
                moveTo(9.2f, 9.4f)
                curveTo(9.2f, 7.854f, 10.454f, 6.6f, 12f, 6.6f)
                curveTo(13.546f, 6.6f, 14.8f, 7.854f, 14.8f, 9.4f)
                curveTo(14.8f, 10.946f, 13.546f, 12.2f, 12f, 12.2f)
                curveTo(10.454f, 12.2f, 9.2f, 10.946f, 9.2f, 9.4f)
                close()
            }
            .build()
    }

    /** Кільце навколо крапки з чотирма рисками. Крапка каже «ви». */
    val myLocation: ImageVector by lazy {
        builder("myLocation")
            .fill {
                moveTo(10.2f, 12f)
                curveTo(10.2f, 11.006f, 11.006f, 10.2f, 12f, 10.2f)
                curveTo(12.994f, 10.2f, 13.8f, 11.006f, 13.8f, 12f)
                curveTo(13.8f, 12.994f, 12.994f, 13.8f, 12f, 13.8f)
                curveTo(11.006f, 13.8f, 10.2f, 12.994f, 10.2f, 12f)
                close()
            }
            .stroke {
                moveTo(6.5f, 12f)
                curveTo(6.5f, 8.962f, 8.962f, 6.5f, 12f, 6.5f)
                curveTo(15.038f, 6.5f, 17.5f, 8.962f, 17.5f, 12f)
                curveTo(17.5f, 15.038f, 15.038f, 17.5f, 12f, 17.5f)
                curveTo(8.962f, 17.5f, 6.5f, 15.038f, 6.5f, 12f)
                close()
                moveTo(12f, 2.5f)
                lineTo(12f, 5f)
                moveTo(12f, 19f)
                lineTo(12f, 21.5f)
                moveTo(2.5f, 12f)
                lineTo(5f, 12f)
                moveTo(19f, 12f)
                lineTo(21.5f, 12f)
            }
            .build()
    }

    /** Чотири дужки навколо крапки: повернути місто в кадр. */
    val recenter: ImageVector by lazy {
        builder("recenter")
            .fill {
                moveTo(9.8f, 12f)
                curveTo(9.8f, 10.785f, 10.785f, 9.8f, 12f, 9.8f)
                curveTo(13.215f, 9.8f, 14.2f, 10.785f, 14.2f, 12f)
                curveTo(14.2f, 13.215f, 13.215f, 14.2f, 12f, 14.2f)
                curveTo(10.785f, 14.2f, 9.8f, 13.215f, 9.8f, 12f)
                close()
            }
            .stroke {
                moveTo(3.5f, 9f)
                lineTo(3.5f, 5.8f)
                curveTo(3.5f, 4.5f, 4.5f, 3.5f, 5.8f, 3.5f)
                lineTo(9f, 3.5f)
                moveTo(15f, 3.5f)
                lineTo(18.2f, 3.5f)
                curveTo(19.5f, 3.5f, 20.5f, 4.5f, 20.5f, 5.8f)
                lineTo(20.5f, 9f)
                moveTo(20.5f, 15f)
                lineTo(20.5f, 18.2f)
                curveTo(20.5f, 19.5f, 19.5f, 20.5f, 18.2f, 20.5f)
                lineTo(15f, 20.5f)
                moveTo(9f, 20.5f)
                lineTo(5.8f, 20.5f)
                curveTo(4.5f, 20.5f, 3.5f, 19.5f, 3.5f, 18.2f)
                lineTo(3.5f, 15f)
            }
            .build()
    }

    /** Чотирикутна зірка з увігнутими боками, контуром. */
    val sparkle: ImageVector by lazy {
        builder("sparkle")
            .stroke {
                moveTo(12f, 3f)
                curveTo(12.8f, 8.6f, 15.4f, 11.2f, 21f, 12f)
                curveTo(15.4f, 12.8f, 12.8f, 15.4f, 12f, 21f)
                curveTo(11.2f, 15.4f, 8.6f, 12.8f, 3f, 12f)
                curveTo(8.6f, 11.2f, 11.2f, 8.6f, 12f, 3f)
                close()
            }
            .build()
    }

    /** Замок: дужка, корпус, крапка шпарини. */
    val lock: ImageVector by lazy {
        builder("lock")
            .fill {
                moveTo(10.5f, 15.5f)
                curveTo(10.5f, 14.672f, 11.172f, 14f, 12f, 14f)
                curveTo(12.828f, 14f, 13.5f, 14.672f, 13.5f, 15.5f)
                curveTo(13.5f, 16.328f, 12.828f, 17f, 12f, 17f)
                curveTo(11.172f, 17f, 10.5f, 16.328f, 10.5f, 15.5f)
                close()
            }
            .stroke {
                moveTo(8f, 10.5f)
                lineTo(8f, 8f)
                curveTo(8f, 5.8f, 9.8f, 4f, 12f, 4f)
                curveTo(14.2f, 4f, 16f, 5.8f, 16f, 8f)
                lineTo(16f, 10.5f)
                moveTo(7.5f, 10.5f)
                lineTo(16.5f, 10.5f)
                curveTo(18.157f, 10.5f, 19.5f, 11.843f, 19.5f, 13.5f)
                lineTo(19.5f, 17.5f)
                curveTo(19.5f, 19.157f, 18.157f, 20.5f, 16.5f, 20.5f)
                lineTo(7.5f, 20.5f)
                curveTo(5.843f, 20.5f, 4.5f, 19.157f, 4.5f, 17.5f)
                lineTo(4.5f, 13.5f)
                curveTo(4.5f, 11.843f, 5.843f, 10.5f, 7.5f, 10.5f)
                close()
            }
            .build()
    }

    val checkCircle: ImageVector by lazy {
        builder("checkCircle")
            .stroke {
                moveTo(3.5f, 12f)
                curveTo(3.5f, 7.306f, 7.306f, 3.5f, 12f, 3.5f)
                curveTo(16.694f, 3.5f, 20.5f, 7.306f, 20.5f, 12f)
                curveTo(20.5f, 16.694f, 16.694f, 20.5f, 12f, 20.5f)
                curveTo(7.306f, 20.5f, 3.5f, 16.694f, 3.5f, 12f)
                close()
                moveTo(8.2f, 12.3f)
                lineTo(10.9f, 15f)
                lineTo(15.9f, 9.5f)
            }
            .build()
    }

    val alert: ImageVector by lazy {
        builder("alert")
            .fill {
                moveTo(10.75f, 16.4f)
                curveTo(10.75f, 15.71f, 11.31f, 15.15f, 12f, 15.15f)
                curveTo(12.69f, 15.15f, 13.25f, 15.71f, 13.25f, 16.4f)
                curveTo(13.25f, 17.09f, 12.69f, 17.65f, 12f, 17.65f)
                curveTo(11.31f, 17.65f, 10.75f, 17.09f, 10.75f, 16.4f)
                close()
            }
            .stroke {
                moveTo(3.5f, 12f)
                curveTo(3.5f, 7.306f, 7.306f, 3.5f, 12f, 3.5f)
                curveTo(16.694f, 3.5f, 20.5f, 7.306f, 20.5f, 12f)
                curveTo(20.5f, 16.694f, 16.694f, 20.5f, 12f, 20.5f)
                curveTo(7.306f, 20.5f, 3.5f, 16.694f, 3.5f, 12f)
                close()
                moveTo(12f, 7.5f)
                lineTo(12f, 13f)
            }
            .build()
    }

    val clock: ImageVector by lazy {
        builder("clock")
            .stroke {
                moveTo(3.5f, 12f)
                curveTo(3.5f, 7.306f, 7.306f, 3.5f, 12f, 3.5f)
                curveTo(16.694f, 3.5f, 20.5f, 7.306f, 20.5f, 12f)
                curveTo(20.5f, 16.694f, 16.694f, 20.5f, 12f, 20.5f)
                curveTo(7.306f, 20.5f, 3.5f, 16.694f, 3.5f, 12f)
                close()
                moveTo(12f, 7.5f)
                lineTo(12f, 12f)
                lineTo(15.4f, 14.1f)
            }
            .build()
    }

    /** Пісочний годинник для черги: час минає, а не помилка. */
    val queue: ImageVector by lazy {
        builder("queue")
            .stroke {
                moveTo(7f, 3.5f)
                lineTo(17f, 3.5f)
                moveTo(7f, 20.5f)
                lineTo(17f, 20.5f)
                moveTo(8.5f, 3.5f)
                lineTo(8.5f, 7f)
                curveTo(8.5f, 10f, 12f, 11f, 12f, 12f)
                curveTo(12f, 13f, 8.5f, 14f, 8.5f, 17f)
                lineTo(8.5f, 20.5f)
                moveTo(15.5f, 3.5f)
                lineTo(15.5f, 7f)
                curveTo(15.5f, 10f, 12f, 11f, 12f, 12f)
                curveTo(12f, 13f, 15.5f, 14f, 15.5f, 17f)
                lineTo(15.5f, 20.5f)
            }
            .build()
    }

    private fun builder(name: String) =
        ImageVector.Builder("Poruch.$name", SIZE.dp, SIZE.dp, SIZE, SIZE)

    private inline fun ImageVector.Builder.stroke(block: androidx.compose.ui.graphics.vector.PathBuilder.() -> Unit) =
        path(
            stroke = SolidColor(Color.Black), strokeLineWidth = STROKE,
            strokeLineCap = StrokeCap.Round, strokeLineJoin = StrokeJoin.Round,
            pathBuilder = block
        )

    private inline fun ImageVector.Builder.fill(block: androidx.compose.ui.graphics.vector.PathBuilder.() -> Unit) =
        path(fill = SolidColor(Color.Black), pathBuilder = block)

    /** Один шлях, де внутрішні підшляхи вирізають дірки в зовнішньому. */
    private inline fun ImageVector.Builder.punch(block: androidx.compose.ui.graphics.vector.PathBuilder.() -> Unit) =
        path(fill = SolidColor(Color.Black), pathFillType = PathFillType.EvenOdd, pathBuilder = block)
}

private const val SIZE = 24f
private const val STROKE = 1.75f
