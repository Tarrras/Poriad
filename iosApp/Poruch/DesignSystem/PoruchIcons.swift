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
