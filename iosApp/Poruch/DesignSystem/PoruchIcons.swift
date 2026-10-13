import SwiftUI

/// Власні гліфи застосунку: тонка лінія на сітці 24, заливка лише для крапок.
///
/// ЗГЕНЕРОВАНО tools/generate_icons.py: геометрію правити там, інакше Kotlin-двійник у
/// ui/PoruchIcons.kt розійдеться з цим файлом.
///
/// Гліф без кольору: `PoruchIcon` малює поточним foreground, тож `.foregroundStyle(…)` працює як для SF Symbol.
struct PoruchGlyph {
    let stroke: ((inout Path, CGFloat) -> Void)?
    let fill: ((inout Path, CGFloat) -> Void)?
    /// Один шлях, де внутрішні підшляхи вирізають дірки в зовнішньому.
    let punch: ((inout Path, CGFloat) -> Void)?

    init(
        stroke: ((inout Path, CGFloat) -> Void)? = nil,
        fill: ((inout Path, CGFloat) -> Void)? = nil,
        punch: ((inout Path, CGFloat) -> Void)? = nil
    ) {
        self.stroke = stroke
        self.fill = fill
        self.punch = punch
    }
}

enum PoruchIcons {
    /// Восьма нота: кільце головки, стебло і прапорець однією кривою.
    static let music = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(5.5, 16.5, s))
            path.addCurve(to: point(8.5, 13.5, s), control1: point(5.5, 14.843, s), control2: point(6.843, 13.5, s))
            path.addCurve(to: point(11.5, 16.5, s), control1: point(10.157, 13.5, s), control2: point(11.5, 14.843, s))
            path.addCurve(to: point(8.5, 19.5, s), control1: point(11.5, 18.157, s), control2: point(10.157, 19.5, s))
            path.addCurve(to: point(5.5, 16.5, s), control1: point(6.843, 19.5, s), control2: point(5.5, 18.157, s))
            path.closeSubpath()
            path.move(to: point(11.5, 16.5, s))
            path.addLine(to: point(11.5, 4.5, s))
            path.move(to: point(11.5, 4.5, s))
            path.addCurve(to: point(18, 10.5, s), control1: point(14.5, 5, s), control2: point(18, 6.5, s))
        }
    )

    /// Вимпел на держаку. М'яч був би третім колом у наборі.
    static let sport = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(6.5, 3.5, s))
            path.addLine(to: point(6.5, 20.5, s))
            path.move(to: point(6.5, 4.5, s))
            path.addLine(to: point(18.5, 8.2, s))
            path.addLine(to: point(6.5, 11.9, s))
            path.closeSubpath()
        }
    )

    /// Пензель: короткий держак і великий лист щетини. Голова займає пів гліфа, інакше на піні лишається сама риска.
    static let art = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(4, 20, s))
            path.addLine(to: point(9.8, 14.2, s))
        },
        fill: { path, s in
            path.move(to: point(8.4, 15.6, s))
            path.addCurve(to: point(20.6, 3.4, s), control1: point(8.6, 10.6, s), control2: point(13.6, 5, s))
            path.addCurve(to: point(8.4, 15.6, s), control1: point(19, 10.4, s), control2: point(13.4, 15.4, s))
            path.closeSubpath()
        }
    )

    /// Миска під двома завитками пари.
    static let food = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(9.5, 8.5, s))
            path.addCurve(to: point(11, 4.5, s), control1: point(9.5, 7, s), control2: point(11, 6.5, s))
            path.move(to: point(14, 8.5, s))
            path.addCurve(to: point(15.5, 4.5, s), control1: point(14, 7, s), control2: point(15.5, 6.5, s))
            path.move(to: point(4, 11.5, s))
            path.addLine(to: point(20, 11.5, s))
            path.move(to: point(4.5, 11.5, s))
            path.addCurve(to: point(12, 20, s), control1: point(4.5, 16.5, s), control2: point(7.8, 20, s))
            path.addCurve(to: point(19.5, 11.5, s), control1: point(16.2, 20, s), control2: point(19.5, 16.5, s))
        }
    )

    /// Гральний кубик контуром із трьома очками по діагоналі.
    static let games = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(8.1, 4.5, s))
            path.addLine(to: point(15.9, 4.5, s))
            path.addCurve(to: point(19.5, 8.1, s), control1: point(17.888, 4.5, s), control2: point(19.5, 6.112, s))
            path.addLine(to: point(19.5, 15.9, s))
            path.addCurve(to: point(15.9, 19.5, s), control1: point(19.5, 17.888, s), control2: point(17.888, 19.5, s))
            path.addLine(to: point(8.1, 19.5, s))
            path.addCurve(to: point(4.5, 15.9, s), control1: point(6.112, 19.5, s), control2: point(4.5, 17.888, s))
            path.addLine(to: point(4.5, 8.1, s))
            path.addCurve(to: point(8.1, 4.5, s), control1: point(4.5, 6.112, s), control2: point(6.112, 4.5, s))
            path.closeSubpath()
        },
        fill: { path, s in
            path.move(to: point(7.25, 8.6, s))
            path.addCurve(to: point(8.6, 7.25, s), control1: point(7.25, 7.854, s), control2: point(7.854, 7.25, s))
            path.addCurve(to: point(9.95, 8.6, s), control1: point(9.346, 7.25, s), control2: point(9.95, 7.854, s))
            path.addCurve(to: point(8.6, 9.95, s), control1: point(9.95, 9.346, s), control2: point(9.346, 9.95, s))
            path.addCurve(to: point(7.25, 8.6, s), control1: point(7.854, 9.95, s), control2: point(7.25, 9.346, s))
            path.closeSubpath()
            path.move(to: point(10.65, 12, s))
            path.addCurve(to: point(12, 10.65, s), control1: point(10.65, 11.254, s), control2: point(11.254, 10.65, s))
            path.addCurve(to: point(13.35, 12, s), control1: point(12.746, 10.65, s), control2: point(13.35, 11.254, s))
            path.addCurve(to: point(12, 13.35, s), control1: point(13.35, 12.746, s), control2: point(12.746, 13.35, s))
            path.addCurve(to: point(10.65, 12, s), control1: point(11.254, 13.35, s), control2: point(10.65, 12.746, s))
            path.closeSubpath()
            path.move(to: point(14.05, 15.4, s))
            path.addCurve(to: point(15.4, 14.05, s), control1: point(14.05, 14.654, s), control2: point(14.654, 14.05, s))
            path.addCurve(to: point(16.75, 15.4, s), control1: point(16.146, 14.05, s), control2: point(16.75, 14.654, s))
            path.addCurve(to: point(15.4, 16.75, s), control1: point(16.75, 16.146, s), control2: point(16.146, 16.75, s))
            path.addCurve(to: point(14.05, 15.4, s), control1: point(14.654, 16.75, s), control2: point(14.05, 16.146, s))
            path.closeSubpath()
        }
    )

    /// Ялина двома ярусами і стовбур.
    static let outdoors = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(12, 3.5, s))
            path.addLine(to: point(7.5, 10.8, s))
            path.addLine(to: point(9.6, 10.8, s))
            path.addLine(to: point(5, 17.5, s))
            path.addLine(to: point(19, 17.5, s))
            path.addLine(to: point(14.4, 10.8, s))
            path.addLine(to: point(16.5, 10.8, s))
            path.closeSubpath()
            path.move(to: point(12, 17.5, s))
            path.addLine(to: point(12, 20.5, s))
        }
    )

    /// Дві фігури одна за одною: друга лише контуром за плечем першої.
    static let social = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(5.7, 8, s))
            path.addCurve(to: point(9, 4.7, s), control1: point(5.7, 6.177, s), control2: point(7.177, 4.7, s))
            path.addCurve(to: point(12.3, 8, s), control1: point(10.823, 4.7, s), control2: point(12.3, 6.177, s))
            path.addCurve(to: point(9, 11.3, s), control1: point(12.3, 9.823, s), control2: point(10.823, 11.3, s))
            path.addCurve(to: point(5.7, 8, s), control1: point(7.177, 11.3, s), control2: point(5.7, 9.823, s))
            path.closeSubpath()
            path.move(to: point(3.5, 20, s))
            path.addCurve(to: point(9, 13.3, s), control1: point(3.5, 15.6, s), control2: point(6, 13.3, s))
            path.addCurve(to: point(14.5, 20, s), control1: point(12, 13.3, s), control2: point(14.5, 15.6, s))
            path.move(to: point(15, 5.3, s))
            path.addCurve(to: point(18.3, 9, s), control1: point(17, 5.8, s), control2: point(18.3, 7.3, s))
            path.addCurve(to: point(17, 11.7, s), control1: point(18.3, 10.2, s), control2: point(17.8, 11.1, s))
            path.move(to: point(16.5, 13.6, s))
            path.addCurve(to: point(20.5, 20, s), control1: point(19, 14.2, s), control2: point(20.5, 16.5, s))
        }
    )

    /// Мікрофон: капсула, тримач, стійка.
    static let comedy = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(12, 3, s))
            path.addLine(to: point(12, 3, s))
            path.addCurve(to: point(14.5, 5.5, s), control1: point(13.381, 3, s), control2: point(14.5, 4.119, s))
            path.addLine(to: point(14.5, 10.5, s))
            path.addCurve(to: point(12, 13, s), control1: point(14.5, 11.881, s), control2: point(13.381, 13, s))
            path.addLine(to: point(12, 13, s))
            path.addCurve(to: point(9.5, 10.5, s), control1: point(10.619, 13, s), control2: point(9.5, 11.881, s))
            path.addLine(to: point(9.5, 5.5, s))
            path.addCurve(to: point(12, 3, s), control1: point(9.5, 4.119, s), control2: point(10.619, 3, s))
            path.closeSubpath()
            path.move(to: point(6.8, 10, s))
            path.addCurve(to: point(12, 15.5, s), control1: point(6.8, 13.2, s), control2: point(9.1, 15.5, s))
            path.addCurve(to: point(17.2, 10, s), control1: point(14.9, 15.5, s), control2: point(17.2, 13.2, s))
            path.move(to: point(12, 15.5, s))
            path.addLine(to: point(12, 19.5, s))
            path.move(to: point(8.8, 19.5, s))
            path.addLine(to: point(15.2, 19.5, s))
        }
    )

    /// Кулька на нитці з вузликом.
    static let kids = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(6.7, 8.8, s))
            path.addCurve(to: point(12, 3.5, s), control1: point(6.7, 5.873, s), control2: point(9.073, 3.5, s))
            path.addCurve(to: point(17.3, 8.8, s), control1: point(14.927, 3.5, s), control2: point(17.3, 5.873, s))
            path.addCurve(to: point(12, 14.1, s), control1: point(17.3, 11.727, s), control2: point(14.927, 14.1, s))
            path.addCurve(to: point(6.7, 8.8, s), control1: point(9.073, 14.1, s), control2: point(6.7, 11.727, s))
            path.closeSubpath()
            path.move(to: point(12, 14.1, s))
            path.addLine(to: point(11, 15.6, s))
            path.addLine(to: point(13, 15.6, s))
            path.closeSubpath()
            path.move(to: point(12, 15.6, s))
            path.addCurve(to: point(13.8, 20.5, s), control1: point(12, 17.6, s), control2: point(13.8, 18.4, s))
        }
    )

    /// Брама зі склепінням і прорізом.
    static let tours = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(4, 20.5, s))
            path.addLine(to: point(4, 11.5, s))
            path.addCurve(to: point(12, 3.5, s), control1: point(4, 7.1, s), control2: point(7.6, 3.5, s))
            path.addCurve(to: point(20, 11.5, s), control1: point(16.4, 3.5, s), control2: point(20, 7.1, s))
            path.addLine(to: point(20, 20.5, s))
            path.move(to: point(8.7, 20.5, s))
            path.addLine(to: point(8.7, 12.5, s))
            path.addCurve(to: point(12, 9.2, s), control1: point(8.7, 10.7, s), control2: point(10.2, 9.2, s))
            path.addCurve(to: point(15.3, 12.5, s), control1: point(13.8, 9.2, s), control2: point(15.3, 10.7, s))
            path.addLine(to: point(15.3, 20.5, s))
            path.move(to: point(3, 20.5, s))
            path.addLine(to: point(21, 20.5, s))
        }
    )

    /// Слайд на стійці з двома рядками різної довжини.
    static let conference = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(5.9, 4, s))
            path.addLine(to: point(18.1, 4, s))
            path.addCurve(to: point(20.5, 6.4, s), control1: point(19.425, 4, s), control2: point(20.5, 5.075, s))
            path.addLine(to: point(20.5, 13.6, s))
            path.addCurve(to: point(18.1, 16, s), control1: point(20.5, 14.925, s), control2: point(19.425, 16, s))
            path.addLine(to: point(5.9, 16, s))
            path.addCurve(to: point(3.5, 13.6, s), control1: point(4.575, 16, s), control2: point(3.5, 14.925, s))
            path.addLine(to: point(3.5, 6.4, s))
            path.addCurve(to: point(5.9, 4, s), control1: point(3.5, 5.075, s), control2: point(4.575, 4, s))
            path.closeSubpath()
            path.move(to: point(7.5, 8.3, s))
            path.addLine(to: point(16.5, 8.3, s))
            path.move(to: point(7.5, 11.7, s))
            path.addLine(to: point(13, 11.7, s))
            path.move(to: point(12, 16, s))
            path.addLine(to: point(12, 19.5, s))
            path.move(to: point(8.5, 19.5, s))
            path.addLine(to: point(15.5, 19.5, s))
        }
    )

    /// Дах, стіни й двері трьома лініями.
    static let home = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(3.5, 11.5, s))
            path.addLine(to: point(12, 4, s))
            path.addLine(to: point(20.5, 11.5, s))
            path.move(to: point(5.7, 9.6, s))
            path.addLine(to: point(5.7, 20, s))
            path.addLine(to: point(18.3, 20, s))
            path.addLine(to: point(18.3, 9.6, s))
            path.move(to: point(10, 20, s))
            path.addLine(to: point(10, 14.5, s))
            path.addLine(to: point(14, 14.5, s))
            path.addLine(to: point(14, 20, s))
        }
    )

    /// Складена мапа з двома згинами.
    static let map = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(3.5, 6, s))
            path.addLine(to: point(9, 4, s))
            path.addLine(to: point(15, 6.5, s))
            path.addLine(to: point(20.5, 4.5, s))
            path.addLine(to: point(20.5, 18, s))
            path.addLine(to: point(15, 20, s))
            path.addLine(to: point(9, 17.5, s))
            path.addLine(to: point(3.5, 19.5, s))
            path.closeSubpath()
            path.move(to: point(9, 4, s))
            path.addLine(to: point(9, 17.5, s))
            path.move(to: point(15, 6.5, s))
            path.addLine(to: point(15, 20, s))
        }
    )

    /// Сторінка з шапкою, двома вушками і крапкою сьогоднішнього дня.
    static let calendar = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(6.5, 5, s))
            path.addLine(to: point(17.5, 5, s))
            path.addCurve(to: point(20.5, 8, s), control1: point(19.157, 5, s), control2: point(20.5, 6.343, s))
            path.addLine(to: point(20.5, 17.5, s))
            path.addCurve(to: point(17.5, 20.5, s), control1: point(20.5, 19.157, s), control2: point(19.157, 20.5, s))
            path.addLine(to: point(6.5, 20.5, s))
            path.addCurve(to: point(3.5, 17.5, s), control1: point(4.843, 20.5, s), control2: point(3.5, 19.157, s))
            path.addLine(to: point(3.5, 8, s))
            path.addCurve(to: point(6.5, 5, s), control1: point(3.5, 6.343, s), control2: point(4.843, 5, s))
            path.closeSubpath()
            path.move(to: point(3.5, 10, s))
            path.addLine(to: point(20.5, 10, s))
            path.move(to: point(8, 3, s))
            path.addLine(to: point(8, 7, s))
            path.move(to: point(16, 3, s))
            path.addLine(to: point(16, 7, s))
        },
        fill: { path, s in
            path.move(to: point(10.65, 15, s))
            path.addCurve(to: point(12, 13.65, s), control1: point(10.65, 14.254, s), control2: point(11.254, 13.65, s))
            path.addCurve(to: point(13.35, 15, s), control1: point(12.746, 13.65, s), control2: point(13.35, 14.254, s))
            path.addCurve(to: point(12, 16.35, s), control1: point(13.35, 15.746, s), control2: point(12.746, 16.35, s))
            path.addCurve(to: point(10.65, 15, s), control1: point(11.254, 16.35, s), control2: point(10.65, 15.746, s))
            path.closeSubpath()
        }
    )

    /// Голова й плечі, відкриті знизу, щоб стояти на базовій лінії.
    static let person = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(8.2, 8, s))
            path.addCurve(to: point(12, 4.2, s), control1: point(8.2, 5.901, s), control2: point(9.901, 4.2, s))
            path.addCurve(to: point(15.8, 8, s), control1: point(14.099, 4.2, s), control2: point(15.8, 5.901, s))
            path.addCurve(to: point(12, 11.8, s), control1: point(15.8, 10.099, s), control2: point(14.099, 11.8, s))
            path.addCurve(to: point(8.2, 8, s), control1: point(9.901, 11.8, s), control2: point(8.2, 10.099, s))
            path.closeSubpath()
            path.move(to: point(4.5, 20.5, s))
            path.addCurve(to: point(12, 13.8, s), control1: point(4.5, 16, s), control2: point(7.8, 13.8, s))
            path.addCurve(to: point(19.5, 20.5, s), control1: point(16.2, 13.8, s), control2: point(19.5, 16, s))
        }
    )

    static let search = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(4, 10.5, s))
            path.addCurve(to: point(10.5, 4, s), control1: point(4, 6.91, s), control2: point(6.91, 4, s))
            path.addCurve(to: point(17, 10.5, s), control1: point(14.09, 4, s), control2: point(17, 6.91, s))
            path.addCurve(to: point(10.5, 17, s), control1: point(17, 14.09, s), control2: point(14.09, 17, s))
            path.addCurve(to: point(4, 10.5, s), control1: point(6.91, 17, s), control2: point(4, 14.09, s))
            path.closeSubpath()
            path.move(to: point(15.3, 15.3, s))
            path.addLine(to: point(20.5, 20.5, s))
        }
    )

    /// Три повзунки: налаштування, а не лійка.
    static let filters = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(4, 7, s))
            path.addLine(to: point(20, 7, s))
            path.move(to: point(4, 12, s))
            path.addLine(to: point(20, 12, s))
            path.move(to: point(4, 17, s))
            path.addLine(to: point(20, 17, s))
        },
        fill: { path, s in
            path.move(to: point(7.1, 7, s))
            path.addCurve(to: point(9, 5.1, s), control1: point(7.1, 5.951, s), control2: point(7.951, 5.1, s))
            path.addCurve(to: point(10.9, 7, s), control1: point(10.049, 5.1, s), control2: point(10.9, 5.951, s))
            path.addCurve(to: point(9, 8.9, s), control1: point(10.9, 8.049, s), control2: point(10.049, 8.9, s))
            path.addCurve(to: point(7.1, 7, s), control1: point(7.951, 8.9, s), control2: point(7.1, 8.049, s))
            path.closeSubpath()
            path.move(to: point(13.1, 12, s))
            path.addCurve(to: point(15, 10.1, s), control1: point(13.1, 10.951, s), control2: point(13.951, 10.1, s))
            path.addCurve(to: point(16.9, 12, s), control1: point(16.049, 10.1, s), control2: point(16.9, 10.951, s))
            path.addCurve(to: point(15, 13.9, s), control1: point(16.9, 13.049, s), control2: point(16.049, 13.9, s))
            path.addCurve(to: point(13.1, 12, s), control1: point(13.951, 13.9, s), control2: point(13.1, 13.049, s))
            path.closeSubpath()
            path.move(to: point(9.1, 17, s))
            path.addCurve(to: point(11, 15.1, s), control1: point(9.1, 15.951, s), control2: point(9.951, 15.1, s))
            path.addCurve(to: point(12.9, 17, s), control1: point(12.049, 15.1, s), control2: point(12.9, 15.951, s))
            path.addCurve(to: point(11, 18.9, s), control1: point(12.9, 18.049, s), control2: point(12.049, 18.9, s))
            path.addCurve(to: point(9.1, 17, s), control1: point(9.951, 18.9, s), control2: point(9.1, 18.049, s))
            path.closeSubpath()
        }
    )

    static let bookmark = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(6, 3.5, s))
            path.addLine(to: point(18, 3.5, s))
            path.addLine(to: point(18, 20.5, s))
            path.addLine(to: point(12, 15.8, s))
            path.addLine(to: point(6, 20.5, s))
            path.closeSubpath()
        }
    )

    /// Збережено: та сама закладка, залита.
    static let bookmarkFilled = PoruchGlyph(
        fill: { path, s in
            path.move(to: point(6, 3.5, s))
            path.addLine(to: point(18, 3.5, s))
            path.addLine(to: point(18, 20.5, s))
            path.addLine(to: point(12, 15.8, s))
            path.addLine(to: point(6, 20.5, s))
            path.closeSubpath()
        }
    )

    static let plus = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(12, 5, s))
            path.addLine(to: point(12, 19, s))
            path.move(to: point(5, 12, s))
            path.addLine(to: point(19, 12, s))
        }
    )

    /// Знак застосунку: крапля з кільцем, у гліфі — контуром.
    static let pin = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(12, 21, s))
            path.addCurve(to: point(4.8, 9.4, s), control1: point(12, 21, s), control2: point(4.8, 13.6, s))
            path.addCurve(to: point(12, 2.8, s), control1: point(4.8, 5.4, s), control2: point(8, 2.8, s))
            path.addCurve(to: point(19.2, 9.4, s), control1: point(16, 2.8, s), control2: point(19.2, 5.4, s))
            path.addCurve(to: point(12, 21, s), control1: point(19.2, 13.6, s), control2: point(12, 21, s))
            path.closeSubpath()
            path.move(to: point(9.2, 9.4, s))
            path.addCurve(to: point(12, 6.6, s), control1: point(9.2, 7.854, s), control2: point(10.454, 6.6, s))
            path.addCurve(to: point(14.8, 9.4, s), control1: point(13.546, 6.6, s), control2: point(14.8, 7.854, s))
            path.addCurve(to: point(12, 12.2, s), control1: point(14.8, 10.946, s), control2: point(13.546, 12.2, s))
            path.addCurve(to: point(9.2, 9.4, s), control1: point(10.454, 12.2, s), control2: point(9.2, 10.946, s))
            path.closeSubpath()
        }
    )

    /// Кільце навколо крапки з чотирма рисками. Крапка каже «ви».
    static let myLocation = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(6.5, 12, s))
            path.addCurve(to: point(12, 6.5, s), control1: point(6.5, 8.962, s), control2: point(8.962, 6.5, s))
            path.addCurve(to: point(17.5, 12, s), control1: point(15.038, 6.5, s), control2: point(17.5, 8.962, s))
            path.addCurve(to: point(12, 17.5, s), control1: point(17.5, 15.038, s), control2: point(15.038, 17.5, s))
            path.addCurve(to: point(6.5, 12, s), control1: point(8.962, 17.5, s), control2: point(6.5, 15.038, s))
            path.closeSubpath()
            path.move(to: point(12, 2.5, s))
            path.addLine(to: point(12, 5, s))
            path.move(to: point(12, 19, s))
            path.addLine(to: point(12, 21.5, s))
            path.move(to: point(2.5, 12, s))
            path.addLine(to: point(5, 12, s))
            path.move(to: point(19, 12, s))
            path.addLine(to: point(21.5, 12, s))
        },
        fill: { path, s in
            path.move(to: point(10.2, 12, s))
            path.addCurve(to: point(12, 10.2, s), control1: point(10.2, 11.006, s), control2: point(11.006, 10.2, s))
            path.addCurve(to: point(13.8, 12, s), control1: point(12.994, 10.2, s), control2: point(13.8, 11.006, s))
            path.addCurve(to: point(12, 13.8, s), control1: point(13.8, 12.994, s), control2: point(12.994, 13.8, s))
            path.addCurve(to: point(10.2, 12, s), control1: point(11.006, 13.8, s), control2: point(10.2, 12.994, s))
            path.closeSubpath()
        }
    )

    /// Чотири дужки навколо крапки: повернути місто в кадр.
    static let recenter = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(3.5, 9, s))
            path.addLine(to: point(3.5, 5.8, s))
            path.addCurve(to: point(5.8, 3.5, s), control1: point(3.5, 4.5, s), control2: point(4.5, 3.5, s))
            path.addLine(to: point(9, 3.5, s))
            path.move(to: point(15, 3.5, s))
            path.addLine(to: point(18.2, 3.5, s))
            path.addCurve(to: point(20.5, 5.8, s), control1: point(19.5, 3.5, s), control2: point(20.5, 4.5, s))
            path.addLine(to: point(20.5, 9, s))
            path.move(to: point(20.5, 15, s))
            path.addLine(to: point(20.5, 18.2, s))
            path.addCurve(to: point(18.2, 20.5, s), control1: point(20.5, 19.5, s), control2: point(19.5, 20.5, s))
            path.addLine(to: point(15, 20.5, s))
            path.move(to: point(9, 20.5, s))
            path.addLine(to: point(5.8, 20.5, s))
            path.addCurve(to: point(3.5, 18.2, s), control1: point(4.5, 20.5, s), control2: point(3.5, 19.5, s))
            path.addLine(to: point(3.5, 15, s))
        },
        fill: { path, s in
            path.move(to: point(9.8, 12, s))
            path.addCurve(to: point(12, 9.8, s), control1: point(9.8, 10.785, s), control2: point(10.785, 9.8, s))
            path.addCurve(to: point(14.2, 12, s), control1: point(13.215, 9.8, s), control2: point(14.2, 10.785, s))
            path.addCurve(to: point(12, 14.2, s), control1: point(14.2, 13.215, s), control2: point(13.215, 14.2, s))
            path.addCurve(to: point(9.8, 12, s), control1: point(10.785, 14.2, s), control2: point(9.8, 13.215, s))
            path.closeSubpath()
        }
    )

    /// Чотирикутна зірка з увігнутими боками, контуром.
    static let sparkle = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(12, 3, s))
            path.addCurve(to: point(21, 12, s), control1: point(12.8, 8.6, s), control2: point(15.4, 11.2, s))
            path.addCurve(to: point(12, 21, s), control1: point(15.4, 12.8, s), control2: point(12.8, 15.4, s))
            path.addCurve(to: point(3, 12, s), control1: point(11.2, 15.4, s), control2: point(8.6, 12.8, s))
            path.addCurve(to: point(12, 3, s), control1: point(8.6, 11.2, s), control2: point(11.2, 8.6, s))
            path.closeSubpath()
        }
    )

    /// Замок: дужка, корпус, крапка шпарини.
    static let lock = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(8, 10.5, s))
            path.addLine(to: point(8, 8, s))
            path.addCurve(to: point(12, 4, s), control1: point(8, 5.8, s), control2: point(9.8, 4, s))
            path.addCurve(to: point(16, 8, s), control1: point(14.2, 4, s), control2: point(16, 5.8, s))
            path.addLine(to: point(16, 10.5, s))
            path.move(to: point(7.5, 10.5, s))
            path.addLine(to: point(16.5, 10.5, s))
            path.addCurve(to: point(19.5, 13.5, s), control1: point(18.157, 10.5, s), control2: point(19.5, 11.843, s))
            path.addLine(to: point(19.5, 17.5, s))
            path.addCurve(to: point(16.5, 20.5, s), control1: point(19.5, 19.157, s), control2: point(18.157, 20.5, s))
            path.addLine(to: point(7.5, 20.5, s))
            path.addCurve(to: point(4.5, 17.5, s), control1: point(5.843, 20.5, s), control2: point(4.5, 19.157, s))
            path.addLine(to: point(4.5, 13.5, s))
            path.addCurve(to: point(7.5, 10.5, s), control1: point(4.5, 11.843, s), control2: point(5.843, 10.5, s))
            path.closeSubpath()
        },
        fill: { path, s in
            path.move(to: point(10.5, 15.5, s))
            path.addCurve(to: point(12, 14, s), control1: point(10.5, 14.672, s), control2: point(11.172, 14, s))
            path.addCurve(to: point(13.5, 15.5, s), control1: point(12.828, 14, s), control2: point(13.5, 14.672, s))
            path.addCurve(to: point(12, 17, s), control1: point(13.5, 16.328, s), control2: point(12.828, 17, s))
            path.addCurve(to: point(10.5, 15.5, s), control1: point(11.172, 17, s), control2: point(10.5, 16.328, s))
            path.closeSubpath()
        }
    )

    static let checkCircle = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(3.5, 12, s))
            path.addCurve(to: point(12, 3.5, s), control1: point(3.5, 7.306, s), control2: point(7.306, 3.5, s))
            path.addCurve(to: point(20.5, 12, s), control1: point(16.694, 3.5, s), control2: point(20.5, 7.306, s))
            path.addCurve(to: point(12, 20.5, s), control1: point(20.5, 16.694, s), control2: point(16.694, 20.5, s))
            path.addCurve(to: point(3.5, 12, s), control1: point(7.306, 20.5, s), control2: point(3.5, 16.694, s))
            path.closeSubpath()
            path.move(to: point(8.2, 12.3, s))
            path.addLine(to: point(10.9, 15, s))
            path.addLine(to: point(15.9, 9.5, s))
        }
    )

    static let alert = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(3.5, 12, s))
            path.addCurve(to: point(12, 3.5, s), control1: point(3.5, 7.306, s), control2: point(7.306, 3.5, s))
            path.addCurve(to: point(20.5, 12, s), control1: point(16.694, 3.5, s), control2: point(20.5, 7.306, s))
            path.addCurve(to: point(12, 20.5, s), control1: point(20.5, 16.694, s), control2: point(16.694, 20.5, s))
            path.addCurve(to: point(3.5, 12, s), control1: point(7.306, 20.5, s), control2: point(3.5, 16.694, s))
            path.closeSubpath()
            path.move(to: point(12, 7.5, s))
            path.addLine(to: point(12, 13, s))
        },
        fill: { path, s in
            path.move(to: point(10.75, 16.4, s))
            path.addCurve(to: point(12, 15.15, s), control1: point(10.75, 15.71, s), control2: point(11.31, 15.15, s))
            path.addCurve(to: point(13.25, 16.4, s), control1: point(12.69, 15.15, s), control2: point(13.25, 15.71, s))
            path.addCurve(to: point(12, 17.65, s), control1: point(13.25, 17.09, s), control2: point(12.69, 17.65, s))
            path.addCurve(to: point(10.75, 16.4, s), control1: point(11.31, 17.65, s), control2: point(10.75, 17.09, s))
            path.closeSubpath()
        }
    )

    static let clock = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(3.5, 12, s))
            path.addCurve(to: point(12, 3.5, s), control1: point(3.5, 7.306, s), control2: point(7.306, 3.5, s))
            path.addCurve(to: point(20.5, 12, s), control1: point(16.694, 3.5, s), control2: point(20.5, 7.306, s))
            path.addCurve(to: point(12, 20.5, s), control1: point(20.5, 16.694, s), control2: point(16.694, 20.5, s))
            path.addCurve(to: point(3.5, 12, s), control1: point(7.306, 20.5, s), control2: point(3.5, 16.694, s))
            path.closeSubpath()
            path.move(to: point(12, 7.5, s))
            path.addLine(to: point(12, 12, s))
            path.addLine(to: point(15.4, 14.1, s))
        }
    )

    /// Пісочний годинник для черги: час минає, а не помилка.
    static let queue = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(7, 3.5, s))
            path.addLine(to: point(17, 3.5, s))
            path.move(to: point(7, 20.5, s))
            path.addLine(to: point(17, 20.5, s))
            path.move(to: point(8.5, 3.5, s))
            path.addLine(to: point(8.5, 7, s))
            path.addCurve(to: point(12, 12, s), control1: point(8.5, 10, s), control2: point(12, 11, s))
            path.addCurve(to: point(8.5, 17, s), control1: point(12, 13, s), control2: point(8.5, 14, s))
            path.addLine(to: point(8.5, 20.5, s))
            path.move(to: point(15.5, 3.5, s))
            path.addLine(to: point(15.5, 7, s))
            path.addCurve(to: point(12, 12, s), control1: point(15.5, 10, s), control2: point(12, 11, s))
            path.addCurve(to: point(15.5, 17, s), control1: point(12, 13, s), control2: point(15.5, 14, s))
            path.addLine(to: point(15.5, 20.5, s))
        }
    )

    static let chevronRight = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(9.5, 6, s))
            path.addLine(to: point(15.5, 12, s))
            path.addLine(to: point(9.5, 18, s))
        }
    )

    /// «Назад».
    static let chevronLeft = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(14.5, 6, s))
            path.addLine(to: point(8.5, 12, s))
            path.addLine(to: point(14.5, 18, s))
        }
    )

    static let chevronDown = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(6, 9.5, s))
            path.addLine(to: point(12, 15.5, s))
            path.addLine(to: point(18, 9.5, s))
        }
    )

    static let chevronUp = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(6, 14.5, s))
            path.addLine(to: point(12, 8.5, s))
            path.addLine(to: point(18, 14.5, s))
        }
    )

    static let check = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(5, 12.5, s))
            path.addLine(to: point(9.8, 17.3, s))
            path.addLine(to: point(19, 8, s))
        }
    )

    static let close = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(6, 6, s))
            path.addLine(to: point(18, 18, s))
            path.move(to: point(18, 6, s))
            path.addLine(to: point(6, 18, s))
        }
    )

    /// Очистити поле, скасувати.
    static let closeCircle = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(3.5, 12, s))
            path.addCurve(to: point(12, 3.5, s), control1: point(3.5, 7.306, s), control2: point(7.306, 3.5, s))
            path.addCurve(to: point(20.5, 12, s), control1: point(16.694, 3.5, s), control2: point(20.5, 7.306, s))
            path.addCurve(to: point(12, 20.5, s), control1: point(20.5, 16.694, s), control2: point(16.694, 20.5, s))
            path.addCurve(to: point(3.5, 12, s), control1: point(7.306, 20.5, s), control2: point(3.5, 16.694, s))
            path.closeSubpath()
            path.move(to: point(8.8, 8.8, s))
            path.addLine(to: point(15.2, 15.2, s))
            path.move(to: point(15.2, 8.8, s))
            path.addLine(to: point(8.8, 15.2, s))
        }
    )

    static let minus = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(5, 12, s))
            path.addLine(to: point(19, 12, s))
        }
    )

    static let arrowRight = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(4.5, 12, s))
            path.addLine(to: point(19.5, 12, s))
            path.move(to: point(13.5, 6, s))
            path.addLine(to: point(19.5, 12, s))
            path.addLine(to: point(13.5, 18, s))
        }
    )

    /// Надіслати.
    static let arrowUp = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(12, 19.5, s))
            path.addLine(to: point(12, 4.5, s))
            path.move(to: point(6, 10.5, s))
            path.addLine(to: point(12, 4.5, s))
            path.addLine(to: point(18, 10.5, s))
        }
    )

    /// Стрілка з коробки вгору: «поділитися» однаково на обох платформах.
    static let share = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(8.5, 9.5, s))
            path.addLine(to: point(5.5, 9.5, s))
            path.addLine(to: point(5.5, 20, s))
            path.addLine(to: point(18.5, 20, s))
            path.addLine(to: point(18.5, 9.5, s))
            path.addLine(to: point(15.5, 9.5, s))
            path.move(to: point(12, 14.5, s))
            path.addLine(to: point(12, 3.5, s))
            path.move(to: point(8.5, 7, s))
            path.addLine(to: point(12, 3.5, s))
            path.addLine(to: point(15.5, 7, s))
        }
    )

    /// Маршрут: поворот угору й праворуч.
    static let directions = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(5, 20, s))
            path.addLine(to: point(5, 13, s))
            path.addCurve(to: point(7, 11, s), control1: point(5, 11.9, s), control2: point(5.9, 11, s))
            path.addLine(to: point(18.5, 11, s))
            path.move(to: point(14, 6.5, s))
            path.addLine(to: point(18.5, 11, s))
            path.addLine(to: point(14, 15.5, s))
        }
    )

    /// Бульбашка з хвостиком.
    static let chat = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(7, 4.5, s))
            path.addLine(to: point(17, 4.5, s))
            path.addCurve(to: point(20.5, 8, s), control1: point(18.933, 4.5, s), control2: point(20.5, 6.067, s))
            path.addLine(to: point(20.5, 13.5, s))
            path.addCurve(to: point(17, 17, s), control1: point(20.5, 15.433, s), control2: point(18.933, 17, s))
            path.addLine(to: point(7, 17, s))
            path.addCurve(to: point(3.5, 13.5, s), control1: point(5.067, 17, s), control2: point(3.5, 15.433, s))
            path.addLine(to: point(3.5, 8, s))
            path.addCurve(to: point(7, 4.5, s), control1: point(3.5, 6.067, s), control2: point(5.067, 4.5, s))
            path.closeSubpath()
            path.move(to: point(8, 17, s))
            path.addLine(to: point(8, 20.5, s))
            path.addLine(to: point(12, 17, s))
        }
    )

    static let mail = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(6, 5.5, s))
            path.addLine(to: point(18, 5.5, s))
            path.addCurve(to: point(20.5, 8, s), control1: point(19.381, 5.5, s), control2: point(20.5, 6.619, s))
            path.addLine(to: point(20.5, 16, s))
            path.addCurve(to: point(18, 18.5, s), control1: point(20.5, 17.381, s), control2: point(19.381, 18.5, s))
            path.addLine(to: point(6, 18.5, s))
            path.addCurve(to: point(3.5, 16, s), control1: point(4.619, 18.5, s), control2: point(3.5, 17.381, s))
            path.addLine(to: point(3.5, 8, s))
            path.addCurve(to: point(6, 5.5, s), control1: point(3.5, 6.619, s), control2: point(4.619, 5.5, s))
            path.closeSubpath()
            path.move(to: point(4.5, 7.5, s))
            path.addLine(to: point(12, 13, s))
            path.addLine(to: point(19.5, 7.5, s))
        }
    )

    static let bell = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(6, 16.5, s))
            path.addLine(to: point(18, 16.5, s))
            path.addLine(to: point(16.8, 14.5, s))
            path.addLine(to: point(16.8, 10.5, s))
            path.addCurve(to: point(12, 5.3, s), control1: point(16.8, 7.6, s), control2: point(14.7, 5.3, s))
            path.addCurve(to: point(7.2, 10.5, s), control1: point(9.3, 5.3, s), control2: point(7.2, 7.6, s))
            path.addLine(to: point(7.2, 14.5, s))
            path.closeSubpath()
            path.move(to: point(10.3, 19.2, s))
            path.addCurve(to: point(12, 20.5, s), control1: point(10.7, 20.2, s), control2: point(11.3, 20.5, s))
            path.addCurve(to: point(13.7, 19.2, s), control1: point(12.7, 20.5, s), control2: point(13.3, 20.2, s))
        }
    )

    /// Той самий дзвінок з двома дугами: сповіщення увімкнено.
    static let bellActive = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(6, 16.5, s))
            path.addLine(to: point(18, 16.5, s))
            path.addLine(to: point(16.8, 14.5, s))
            path.addLine(to: point(16.8, 10.5, s))
            path.addCurve(to: point(12, 5.3, s), control1: point(16.8, 7.6, s), control2: point(14.7, 5.3, s))
            path.addCurve(to: point(7.2, 10.5, s), control1: point(9.3, 5.3, s), control2: point(7.2, 7.6, s))
            path.addLine(to: point(7.2, 14.5, s))
            path.closeSubpath()
            path.move(to: point(10.3, 19.2, s))
            path.addCurve(to: point(12, 20.5, s), control1: point(10.7, 20.2, s), control2: point(11.3, 20.5, s))
            path.addCurve(to: point(13.7, 19.2, s), control1: point(12.7, 20.5, s), control2: point(13.3, 20.2, s))
            path.move(to: point(3.5, 9.5, s))
            path.addCurve(to: point(5.8, 4.3, s), control1: point(3.5, 7.3, s), control2: point(4.4, 5.6, s))
            path.move(to: point(20.5, 9.5, s))
            path.addCurve(to: point(18.2, 4.3, s), control1: point(20.5, 7.3, s), control2: point(19.6, 5.6, s))
        }
    )

    /// Олівець.
    static let edit = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(4, 20, s))
            path.addLine(to: point(4.4, 16.2, s))
            path.addLine(to: point(15.8, 4.8, s))
            path.addLine(to: point(19.2, 8.2, s))
            path.addLine(to: point(7.8, 19.6, s))
            path.closeSubpath()
            path.move(to: point(13.4, 7.2, s))
            path.addLine(to: point(16.8, 10.6, s))
        }
    )

    /// Оцінка.
    static let star = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(12, 4, s))
            path.addLine(to: point(14.17, 9.61, s))
            path.addLine(to: point(20.18, 9.94, s))
            path.addLine(to: point(15.52, 13.74, s))
            path.addLine(to: point(17.05, 19.56, s))
            path.addLine(to: point(12, 16.3, s))
            path.addLine(to: point(6.95, 19.56, s))
            path.addLine(to: point(8.48, 13.74, s))
            path.addLine(to: point(3.82, 9.94, s))
            path.addLine(to: point(9.83, 9.61, s))
            path.closeSubpath()
        }
    )

    /// Безпека.
    static let shield = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(12, 3.5, s))
            path.addLine(to: point(19.5, 6.5, s))
            path.addLine(to: point(19.5, 12, s))
            path.addCurve(to: point(12, 21, s), control1: point(19.5, 16.5, s), control2: point(16.5, 19.5, s))
            path.addCurve(to: point(4.5, 12, s), control1: point(7.5, 19.5, s), control2: point(4.5, 16.5, s))
            path.addLine(to: point(4.5, 6.5, s))
            path.closeSubpath()
        }
    )

    static let trash = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(4, 7, s))
            path.addLine(to: point(20, 7, s))
            path.move(to: point(9.5, 7, s))
            path.addLine(to: point(9.5, 4.5, s))
            path.addLine(to: point(14.5, 4.5, s))
            path.addLine(to: point(14.5, 7, s))
            path.move(to: point(6, 7, s))
            path.addLine(to: point(6.8, 20, s))
            path.addLine(to: point(17.2, 20, s))
            path.addLine(to: point(18, 7, s))
            path.move(to: point(10, 10.5, s))
            path.addLine(to: point(10.2, 16.5, s))
            path.move(to: point(14, 10.5, s))
            path.addLine(to: point(13.8, 16.5, s))
        }
    )

    /// Людина з плюсом: запит на участь.
    static let personAdd = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(5.7, 8, s))
            path.addCurve(to: point(9, 4.7, s), control1: point(5.7, 6.177, s), control2: point(7.177, 4.7, s))
            path.addCurve(to: point(12.3, 8, s), control1: point(10.823, 4.7, s), control2: point(12.3, 6.177, s))
            path.addCurve(to: point(9, 11.3, s), control1: point(12.3, 9.823, s), control2: point(10.823, 11.3, s))
            path.addCurve(to: point(5.7, 8, s), control1: point(7.177, 11.3, s), control2: point(5.7, 9.823, s))
            path.closeSubpath()
            path.move(to: point(3.5, 20, s))
            path.addCurve(to: point(9, 13.3, s), control1: point(3.5, 15.6, s), control2: point(6, 13.3, s))
            path.addCurve(to: point(14.5, 20, s), control1: point(12, 13.3, s), control2: point(14.5, 15.6, s))
            path.move(to: point(18.5, 9, s))
            path.addLine(to: point(18.5, 15, s))
            path.move(to: point(15.5, 12, s))
            path.addLine(to: point(21.5, 12, s))
        }
    )

    /// Календар зі знаком оклику: подій нема або скасовано.
    static let calendarAlert = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(6, 5, s))
            path.addLine(to: point(18, 5, s))
            path.addCurve(to: point(20.5, 7.5, s), control1: point(19.381, 5, s), control2: point(20.5, 6.119, s))
            path.addLine(to: point(20.5, 18, s))
            path.addCurve(to: point(18, 20.5, s), control1: point(20.5, 19.381, s), control2: point(19.381, 20.5, s))
            path.addLine(to: point(6, 20.5, s))
            path.addCurve(to: point(3.5, 18, s), control1: point(4.619, 20.5, s), control2: point(3.5, 19.381, s))
            path.addLine(to: point(3.5, 7.5, s))
            path.addCurve(to: point(6, 5, s), control1: point(3.5, 6.119, s), control2: point(4.619, 5, s))
            path.closeSubpath()
            path.move(to: point(3.5, 9.5, s))
            path.addLine(to: point(20.5, 9.5, s))
            path.move(to: point(8, 3, s))
            path.addLine(to: point(8, 6.5, s))
            path.move(to: point(16, 3, s))
            path.addLine(to: point(16, 6.5, s))
            path.move(to: point(12, 12, s))
            path.addLine(to: point(12, 15.5, s))
        },
        fill: { path, s in
            path.move(to: point(10.9, 18, s))
            path.addCurve(to: point(12, 16.9, s), control1: point(10.9, 17.392, s), control2: point(11.392, 16.9, s))
            path.addCurve(to: point(13.1, 18, s), control1: point(12.608, 16.9, s), control2: point(13.1, 17.392, s))
            path.addCurve(to: point(12, 19.1, s), control1: point(13.1, 18.608, s), control2: point(12.608, 19.1, s))
            path.addCurve(to: point(10.9, 18, s), control1: point(11.392, 19.1, s), control2: point(10.9, 18.608, s))
            path.closeSubpath()
        }
    )

    /// Квиток з вирізами й перфорацією.
    static let ticket = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(3.5, 9, s))
            path.addLine(to: point(3.5, 6.5, s))
            path.addLine(to: point(20.5, 6.5, s))
            path.addLine(to: point(20.5, 9, s))
            path.addCurve(to: point(17.5, 12, s), control1: point(18.8, 9, s), control2: point(17.5, 10.3, s))
            path.addCurve(to: point(20.5, 15, s), control1: point(17.5, 13.7, s), control2: point(18.8, 15, s))
            path.addLine(to: point(20.5, 17.5, s))
            path.addLine(to: point(3.5, 17.5, s))
            path.addLine(to: point(3.5, 15, s))
            path.addCurve(to: point(6.5, 12, s), control1: point(5.2, 15, s), control2: point(6.5, 13.7, s))
            path.addCurve(to: point(3.5, 9, s), control1: point(6.5, 10.3, s), control2: point(5.2, 9, s))
            path.closeSubpath()
            path.move(to: point(12, 6.5, s))
            path.addLine(to: point(12, 17.5, s))
        }
    )

    /// Вихід: стрілка з рамки.
    static let signOut = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(13, 4, s))
            path.addLine(to: point(5, 4, s))
            path.addLine(to: point(5, 20, s))
            path.addLine(to: point(13, 20, s))
            path.move(to: point(9.5, 12, s))
            path.addLine(to: point(20, 12, s))
            path.move(to: point(16.5, 8.5, s))
            path.addLine(to: point(20, 12, s))
            path.addLine(to: point(16.5, 15.5, s))
        }
    )

    /// Стрілка до лінії: перейти на джерело.
    static let enter = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(3.5, 12, s))
            path.addLine(to: point(14, 12, s))
            path.move(to: point(10.5, 8.5, s))
            path.addLine(to: point(14, 12, s))
            path.addLine(to: point(10.5, 15.5, s))
            path.move(to: point(18.5, 5, s))
            path.addLine(to: point(18.5, 19, s))
        }
    )

    /// Дві ланки.
    static let link = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(10, 14, s))
            path.addLine(to: point(14, 10, s))
            path.move(to: point(8.5, 11, s))
            path.addLine(to: point(6, 13.5, s))
            path.addCurve(to: point(6, 19.5, s), control1: point(4, 15.5, s), control2: point(4, 18, s))
            path.addCurve(to: point(12, 19, s), control1: point(7.5, 21, s), control2: point(10, 21, s))
            path.addLine(to: point(13.5, 17.5, s))
            path.move(to: point(15.5, 13, s))
            path.addLine(to: point(18, 10.5, s))
            path.addCurve(to: point(18, 4.5, s), control1: point(20, 8.5, s), control2: point(20, 6, s))
            path.addCurve(to: point(12, 5, s), control1: point(16.5, 3, s), control2: point(14, 3, s))
            path.addLine(to: point(10.5, 6.5, s))
        }
    )

    /// Піднята долоня: модерація, скарга.
    static let hand = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(6.5, 12.5, s))
            path.addLine(to: point(6.5, 6.5, s))
            path.addCurve(to: point(8, 5, s), control1: point(6.5, 5.7, s), control2: point(7.2, 5, s))
            path.addCurve(to: point(9.5, 6.5, s), control1: point(8.8, 5, s), control2: point(9.5, 5.7, s))
            path.addLine(to: point(9.5, 4.5, s))
            path.addCurve(to: point(11, 3, s), control1: point(9.5, 3.7, s), control2: point(10.2, 3, s))
            path.addCurve(to: point(12.5, 4.5, s), control1: point(11.8, 3, s), control2: point(12.5, 3.7, s))
            path.addLine(to: point(12.5, 5.5, s))
            path.addCurve(to: point(14, 4, s), control1: point(12.5, 4.7, s), control2: point(13.2, 4, s))
            path.addCurve(to: point(15.5, 5.5, s), control1: point(14.8, 4, s), control2: point(15.5, 4.7, s))
            path.addLine(to: point(15.5, 8, s))
            path.addCurve(to: point(17, 6.5, s), control1: point(15.5, 7.2, s), control2: point(16.2, 6.5, s))
            path.addCurve(to: point(18.5, 8, s), control1: point(17.8, 6.5, s), control2: point(18.5, 7.2, s))
            path.addLine(to: point(18.5, 14, s))
            path.addCurve(to: point(11.5, 21, s), control1: point(18.5, 18, s), control2: point(15.5, 21, s))
            path.addCurve(to: point(5, 16.5, s), control1: point(8.5, 21, s), control2: point(6.5, 19.5, s))
            path.addLine(to: point(3.8, 13.8, s))
            path.addCurve(to: point(4.6, 12, s), control1: point(3.4, 13, s), control2: point(3.8, 12.2, s))
            path.addCurve(to: point(6.5, 12.5, s), control1: point(5.4, 11.8, s), control2: point(6.1, 12.1, s))
            path.closeSubpath()
        }
    )

    /// Куля з меридіанами: усюди.
    static let globe = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(3.5, 12, s))
            path.addCurve(to: point(12, 3.5, s), control1: point(3.5, 7.306, s), control2: point(7.306, 3.5, s))
            path.addCurve(to: point(20.5, 12, s), control1: point(16.694, 3.5, s), control2: point(20.5, 7.306, s))
            path.addCurve(to: point(12, 20.5, s), control1: point(20.5, 16.694, s), control2: point(16.694, 20.5, s))
            path.addCurve(to: point(3.5, 12, s), control1: point(7.306, 20.5, s), control2: point(3.5, 16.694, s))
            path.closeSubpath()
            path.move(to: point(3.5, 12, s))
            path.addLine(to: point(20.5, 12, s))
            path.move(to: point(12, 3.5, s))
            path.addCurve(to: point(12, 20.5, s), control1: point(8.5, 7, s), control2: point(8.5, 17, s))
            path.move(to: point(12, 3.5, s))
            path.addCurve(to: point(12, 20.5, s), control1: point(15.5, 7, s), control2: point(15.5, 17, s))
        }
    )

    /// Аркуш із загнутим кутом: документ.
    static let doc = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(6, 3.5, s))
            path.addLine(to: point(14, 3.5, s))
            path.addLine(to: point(19, 8.5, s))
            path.addLine(to: point(19, 20.5, s))
            path.addLine(to: point(6, 20.5, s))
            path.closeSubpath()
            path.move(to: point(14, 3.5, s))
            path.addLine(to: point(14, 8.5, s))
            path.addLine(to: point(19, 8.5, s))
            path.move(to: point(9, 12.5, s))
            path.addLine(to: point(16, 12.5, s))
            path.move(to: point(9, 16, s))
            path.addLine(to: point(16, 16, s))
        }
    )

    /// Дві дуги зі стрілками.
    static let refresh = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(19.5, 12, s))
            path.addCurve(to: point(12, 4.5, s), control1: point(19.5, 7.9, s), control2: point(16.1, 4.5, s))
            path.addCurve(to: point(5.6, 8, s), control1: point(9.3, 4.5, s), control2: point(6.9, 5.9, s))
            path.move(to: point(4.5, 12, s))
            path.addCurve(to: point(12, 19.5, s), control1: point(4.5, 16.1, s), control2: point(7.9, 19.5, s))
            path.addCurve(to: point(18.4, 16, s), control1: point(14.7, 19.5, s), control2: point(17.1, 18.1, s))
            path.move(to: point(5, 3.5, s))
            path.addLine(to: point(5.6, 8, s))
            path.addLine(to: point(10, 7.5, s))
            path.move(to: point(19, 20.5, s))
            path.addLine(to: point(18.4, 16, s))
            path.addLine(to: point(14, 16.5, s))
        }
    )

    /// Хвилі, перекреслені: звʼязку нема.
    static let wifiOff = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(3, 9, s))
            path.addCurve(to: point(10.3, 5.6, s), control1: point(5, 7.2, s), control2: point(7.5, 6, s))
            path.move(to: point(14.5, 5.8, s))
            path.addCurve(to: point(21, 9, s), control1: point(17, 6.3, s), control2: point(19.2, 7.4, s))
            path.move(to: point(6, 12.5, s))
            path.addCurve(to: point(10.7, 10.3, s), control1: point(7.3, 11.4, s), control2: point(8.9, 10.6, s))
            path.move(to: point(15, 10.8, s))
            path.addCurve(to: point(18, 12.5, s), control1: point(16.1, 11.2, s), control2: point(17.1, 11.8, s))
            path.move(to: point(9, 16, s))
            path.addCurve(to: point(12, 14.9, s), control1: point(9.8, 15.3, s), control2: point(10.9, 14.9, s))
            path.addCurve(to: point(15, 16, s), control1: point(13.1, 14.9, s), control2: point(14.2, 15.3, s))
            path.move(to: point(4, 4, s))
            path.addLine(to: point(20, 20, s))
        },
        fill: { path, s in
            path.move(to: point(10.7, 19.2, s))
            path.addCurve(to: point(12, 17.9, s), control1: point(10.7, 18.482, s), control2: point(11.282, 17.9, s))
            path.addCurve(to: point(13.3, 19.2, s), control1: point(12.718, 17.9, s), control2: point(13.3, 18.482, s))
            path.addCurve(to: point(12, 20.5, s), control1: point(13.3, 19.918, s), control2: point(12.718, 20.5, s))
            path.addCurve(to: point(10.7, 19.2, s), control1: point(11.282, 20.5, s), control2: point(10.7, 19.918, s))
            path.closeSubpath()
        }
    )

    /// Показати пароль.
    static let eye = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(2.5, 12, s))
            path.addCurve(to: point(12, 5.5, s), control1: point(5, 7.5, s), control2: point(8.3, 5.5, s))
            path.addCurve(to: point(21.5, 12, s), control1: point(15.7, 5.5, s), control2: point(19, 7.5, s))
            path.addCurve(to: point(12, 18.5, s), control1: point(19, 16.5, s), control2: point(15.7, 18.5, s))
            path.addCurve(to: point(2.5, 12, s), control1: point(8.3, 18.5, s), control2: point(5, 16.5, s))
            path.closeSubpath()
            path.move(to: point(8.8, 12, s))
            path.addCurve(to: point(12, 8.8, s), control1: point(8.8, 10.233, s), control2: point(10.233, 8.8, s))
            path.addCurve(to: point(15.2, 12, s), control1: point(13.767, 8.8, s), control2: point(15.2, 10.233, s))
            path.addCurve(to: point(12, 15.2, s), control1: point(15.2, 13.767, s), control2: point(13.767, 15.2, s))
            path.addCurve(to: point(8.8, 12, s), control1: point(10.233, 15.2, s), control2: point(8.8, 13.767, s))
            path.closeSubpath()
        }
    )

    /// Сховати пароль.
    static let eyeOff = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(2.5, 12, s))
            path.addCurve(to: point(12, 5.5, s), control1: point(5, 7.5, s), control2: point(8.3, 5.5, s))
            path.addCurve(to: point(21.5, 12, s), control1: point(15.7, 5.5, s), control2: point(19, 7.5, s))
            path.addCurve(to: point(12, 18.5, s), control1: point(19, 16.5, s), control2: point(15.7, 18.5, s))
            path.addCurve(to: point(2.5, 12, s), control1: point(8.3, 18.5, s), control2: point(5, 16.5, s))
            path.closeSubpath()
            path.move(to: point(8.8, 12, s))
            path.addCurve(to: point(12, 8.8, s), control1: point(8.8, 10.233, s), control2: point(10.233, 8.8, s))
            path.addCurve(to: point(15.2, 12, s), control1: point(13.767, 8.8, s), control2: point(15.2, 10.233, s))
            path.addCurve(to: point(12, 15.2, s), control1: point(15.2, 13.767, s), control2: point(13.767, 15.2, s))
            path.addCurve(to: point(8.8, 12, s), control1: point(10.233, 15.2, s), control2: point(8.8, 13.767, s))
            path.closeSubpath()
            path.move(to: point(4, 20, s))
            path.addLine(to: point(20, 4, s))
        }
    )

    /// Вагон метро: укриття в підземці.
    static let subway = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(8, 3.5, s))
            path.addLine(to: point(16, 3.5, s))
            path.addCurve(to: point(19, 6.5, s), control1: point(17.657, 3.5, s), control2: point(19, 4.843, s))
            path.addLine(to: point(19, 14.5, s))
            path.addCurve(to: point(16, 17.5, s), control1: point(19, 16.157, s), control2: point(17.657, 17.5, s))
            path.addLine(to: point(8, 17.5, s))
            path.addCurve(to: point(5, 14.5, s), control1: point(6.343, 17.5, s), control2: point(5, 16.157, s))
            path.addLine(to: point(5, 6.5, s))
            path.addCurve(to: point(8, 3.5, s), control1: point(5, 4.843, s), control2: point(6.343, 3.5, s))
            path.closeSubpath()
            path.move(to: point(5, 11, s))
            path.addLine(to: point(19, 11, s))
            path.move(to: point(8.5, 17.5, s))
            path.addLine(to: point(6.5, 20.5, s))
            path.move(to: point(15.5, 17.5, s))
            path.addLine(to: point(17.5, 20.5, s))
        },
        fill: { path, s in
            path.move(to: point(7.3, 14, s))
            path.addCurve(to: point(8.5, 12.8, s), control1: point(7.3, 13.337, s), control2: point(7.837, 12.8, s))
            path.addCurve(to: point(9.7, 14, s), control1: point(9.163, 12.8, s), control2: point(9.7, 13.337, s))
            path.addCurve(to: point(8.5, 15.2, s), control1: point(9.7, 14.663, s), control2: point(9.163, 15.2, s))
            path.addCurve(to: point(7.3, 14, s), control1: point(7.837, 15.2, s), control2: point(7.3, 14.663, s))
            path.closeSubpath()
            path.move(to: point(14.3, 14, s))
            path.addCurve(to: point(15.5, 12.8, s), control1: point(14.3, 13.337, s), control2: point(14.837, 12.8, s))
            path.addCurve(to: point(16.7, 14, s), control1: point(16.163, 12.8, s), control2: point(16.7, 13.337, s))
            path.addCurve(to: point(15.5, 15.2, s), control1: point(16.7, 14.663, s), control2: point(16.163, 15.2, s))
            path.addCurve(to: point(14.3, 14, s), control1: point(14.837, 15.2, s), control2: point(14.3, 14.663, s))
            path.closeSubpath()
        }
    )

    /// Фотоапарат: обкладинка події.
    static let camera = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(3.5, 8.5, s))
            path.addLine(to: point(8, 8.5, s))
            path.addLine(to: point(9.5, 5.5, s))
            path.addLine(to: point(14.5, 5.5, s))
            path.addLine(to: point(16, 8.5, s))
            path.addLine(to: point(20.5, 8.5, s))
            path.addLine(to: point(20.5, 19, s))
            path.addLine(to: point(3.5, 19, s))
            path.closeSubpath()
            path.move(to: point(8.8, 13.5, s))
            path.addCurve(to: point(12, 10.3, s), control1: point(8.8, 11.733, s), control2: point(10.233, 10.3, s))
            path.addCurve(to: point(15.2, 13.5, s), control1: point(13.767, 10.3, s), control2: point(15.2, 11.733, s))
            path.addCurve(to: point(12, 16.7, s), control1: point(15.2, 15.267, s), control2: point(13.767, 16.7, s))
            path.addCurve(to: point(8.8, 13.5, s), control1: point(10.233, 16.7, s), control2: point(8.8, 15.267, s))
            path.closeSubpath()
        }
    )

    /// Місяць із зірками: комендантська година.
    static let moon = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(13.5, 3.5, s))
            path.addCurve(to: point(6, 12.5, s), control1: point(9, 4.5, s), control2: point(6, 8.5, s))
            path.addCurve(to: point(14.5, 21, s), control1: point(6, 17.2, s), control2: point(9.8, 21, s))
            path.addCurve(to: point(20.8, 18.2, s), control1: point(17, 21, s), control2: point(19.2, 19.9, s))
            path.addCurve(to: point(13.5, 3.5, s), control1: point(15, 18, s), control2: point(11, 13, s))
            path.closeSubpath()
        },
        fill: { path, s in
            path.move(to: point(17.5, 6.5, s))
            path.addCurve(to: point(18.5, 5.5, s), control1: point(17.5, 5.948, s), control2: point(17.948, 5.5, s))
            path.addCurve(to: point(19.5, 6.5, s), control1: point(19.052, 5.5, s), control2: point(19.5, 5.948, s))
            path.addCurve(to: point(18.5, 7.5, s), control1: point(19.5, 7.052, s), control2: point(19.052, 7.5, s))
            path.addCurve(to: point(17.5, 6.5, s), control1: point(17.948, 7.5, s), control2: point(17.5, 7.052, s))
            path.closeSubpath()
            path.move(to: point(19.7, 10.5, s))
            path.addCurve(to: point(20.5, 9.7, s), control1: point(19.7, 10.058, s), control2: point(20.058, 9.7, s))
            path.addCurve(to: point(21.3, 10.5, s), control1: point(20.942, 9.7, s), control2: point(21.3, 10.058, s))
            path.addCurve(to: point(20.5, 11.3, s), control1: point(21.3, 10.942, s), control2: point(20.942, 11.3, s))
            path.addCurve(to: point(19.7, 10.5, s), control1: point(20.058, 11.3, s), control2: point(19.7, 10.942, s))
            path.closeSubpath()
        }
    )

    /// Прапорець: поскаржитись.
    static let flag = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(5.5, 21, s))
            path.addLine(to: point(5.5, 3.5, s))
            path.move(to: point(5.5, 4.5, s))
            path.addLine(to: point(18.5, 4.5, s))
            path.addLine(to: point(15, 9, s))
            path.addLine(to: point(18.5, 13.5, s))
            path.addLine(to: point(5.5, 13.5, s))
        }
    )

    /// Два аркуші: скопіювати.
    static let copy = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(10.5, 8.5, s))
            path.addLine(to: point(18.5, 8.5, s))
            path.addCurve(to: point(20.5, 10.5, s), control1: point(19.605, 8.5, s), control2: point(20.5, 9.395, s))
            path.addLine(to: point(20.5, 18.5, s))
            path.addCurve(to: point(18.5, 20.5, s), control1: point(20.5, 19.605, s), control2: point(19.605, 20.5, s))
            path.addLine(to: point(10.5, 20.5, s))
            path.addCurve(to: point(8.5, 18.5, s), control1: point(9.395, 20.5, s), control2: point(8.5, 19.605, s))
            path.addLine(to: point(8.5, 10.5, s))
            path.addCurve(to: point(10.5, 8.5, s), control1: point(8.5, 9.395, s), control2: point(9.395, 8.5, s))
            path.closeSubpath()
            path.move(to: point(5.5, 15.5, s))
            path.addCurve(to: point(3.5, 13.5, s), control1: point(4.4, 15.5, s), control2: point(3.5, 14.6, s))
            path.addLine(to: point(3.5, 5.5, s))
            path.addCurve(to: point(5.5, 3.5, s), control1: point(3.5, 4.4, s), control2: point(4.4, 3.5, s))
            path.addLine(to: point(13.5, 3.5, s))
            path.addCurve(to: point(15.5, 5.5, s), control1: point(14.6, 3.5, s), control2: point(15.5, 4.4, s))
        }
    )

    /// Хмара, перекреслена: сервер не відповів.
    static let cloudOff = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(7, 18.5, s))
            path.addCurve(to: point(3, 14.7, s), control1: point(4.5, 18.5, s), control2: point(3, 16.8, s))
            path.addCurve(to: point(6.7, 10.8, s), control1: point(3, 12.6, s), control2: point(4.6, 11, s))
            path.addCurve(to: point(12.5, 6, s), control1: point(7.3, 7.9, s), control2: point(9.8, 6, s))
            path.addCurve(to: point(18.1, 9.8, s), control1: point(15, 6, s), control2: point(17.2, 7.5, s))
            path.addCurve(to: point(21, 13.8, s), control1: point(19.9, 10.3, s), control2: point(21, 11.9, s))
            path.addCurve(to: point(16.3, 18.5, s), control1: point(21, 16.4, s), control2: point(18.9, 18.5, s))
            path.addLine(to: point(7, 18.5, s))
            path.move(to: point(4, 4, s))
            path.addLine(to: point(20, 20, s))
        }
    )

    /// Коло з рискою: заблокувати.
    static let block = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(3.5, 12, s))
            path.addCurve(to: point(12, 3.5, s), control1: point(3.5, 7.306, s), control2: point(7.306, 3.5, s))
            path.addCurve(to: point(20.5, 12, s), control1: point(16.694, 3.5, s), control2: point(20.5, 7.306, s))
            path.addCurve(to: point(12, 20.5, s), control1: point(20.5, 16.694, s), control2: point(16.694, 20.5, s))
            path.addCurve(to: point(3.5, 12, s), control1: point(7.306, 20.5, s), control2: point(3.5, 16.694, s))
            path.closeSubpath()
            path.move(to: point(6, 6, s))
            path.addLine(to: point(18, 18, s))
        }
    )

    /// Компас: знайти на мапі.
    static let compass = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(3.5, 12, s))
            path.addCurve(to: point(12, 3.5, s), control1: point(3.5, 7.306, s), control2: point(7.306, 3.5, s))
            path.addCurve(to: point(20.5, 12, s), control1: point(16.694, 3.5, s), control2: point(20.5, 7.306, s))
            path.addCurve(to: point(12, 20.5, s), control1: point(20.5, 16.694, s), control2: point(16.694, 20.5, s))
            path.addCurve(to: point(3.5, 12, s), control1: point(7.306, 20.5, s), control2: point(3.5, 16.694, s))
            path.closeSubpath()
            path.move(to: point(15.5, 8.5, s))
            path.addLine(to: point(13.5, 13.5, s))
            path.addLine(to: point(8.5, 15.5, s))
            path.addLine(to: point(10.5, 10.5, s))
            path.closeSubpath()
        }
    )

    /// Оцінка, поставлена.
    static let starFilled = PoruchGlyph(
        fill: { path, s in
            path.move(to: point(12, 4, s))
            path.addLine(to: point(14.17, 9.61, s))
            path.addLine(to: point(20.18, 9.94, s))
            path.addLine(to: point(15.52, 13.74, s))
            path.addLine(to: point(17.05, 19.56, s))
            path.addLine(to: point(12, 16.3, s))
            path.addLine(to: point(6.95, 19.56, s))
            path.addLine(to: point(8.48, 13.74, s))
            path.addLine(to: point(3.82, 9.94, s))
            path.addLine(to: point(9.83, 9.61, s))
            path.closeSubpath()
        }
    )

    /// «Назад» у шапці.
    static let arrowLeft = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(19.5, 12, s))
            path.addLine(to: point(4.5, 12, s))
            path.move(to: point(10.5, 6, s))
            path.addLine(to: point(4.5, 12, s))
            path.addLine(to: point(10.5, 18, s))
        }
    )

    /// Вхід: стрілка в рамку.
    static let signIn = PoruchGlyph(
        stroke: { path, s in
            path.move(to: point(11, 4, s))
            path.addLine(to: point(19, 4, s))
            path.addLine(to: point(19, 20, s))
            path.addLine(to: point(11, 20, s))
            path.move(to: point(3.5, 12, s))
            path.addLine(to: point(14, 12, s))
            path.move(to: point(10.5, 8.5, s))
            path.addLine(to: point(14, 12, s))
            path.addLine(to: point(10.5, 15.5, s))
        }
    )

}

private func point(_ x: CGFloat, _ y: CGFloat, _ s: CGFloat) -> CGPoint {
    CGPoint(x: x * s, y: y * s)
}

/// Малює `PoruchGlyph` заданого розміру, масштабуючи сітку 24 разом зі штрихом.
struct PoruchIcon: View {
    let glyph: PoruchGlyph
    var size: CGFloat = 20

    var body: some View {
        ZStack {
            if glyph.punch != nil {
                GlyphShape(draw: glyph.punch).fill(style: FillStyle(eoFill: true))
            }
            if glyph.fill != nil {
                GlyphShape(draw: glyph.fill).fill()
            }
            if glyph.stroke != nil {
                GlyphShape(draw: glyph.stroke).stroke(style: StrokeStyle(
                    lineWidth: PoruchIconMetrics.stroke * scale,
                    lineCap: .round, lineJoin: .round
                ))
            }
        }
        .frame(width: size, height: size)
    }

    private var scale: CGFloat { size / PoruchIconMetrics.grid }
}

private struct GlyphShape: Shape {
    let draw: ((inout Path, CGFloat) -> Void)?

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let draw else { return path }
        draw(&path, min(rect.width, rect.height) / PoruchIconMetrics.grid)
        return path
    }
}

enum PoruchIconMetrics {
    static let grid: CGFloat = 24
    static let stroke: CGFloat = 1.75
}
