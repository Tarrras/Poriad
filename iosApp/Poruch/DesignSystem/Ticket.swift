import SwiftUI
import Shared

// ---- Квиток («Корінець»)

/// Форма квитка: скруглений прямокутник із двома півкруглими вирізами на лінії відриву. `stub` — довжина корінця від
/// кінцевого краю: праворуч у горизонтального квитка, знизу у вертикального.
struct TicketShape: Shape {
    var vertical = false
    var stub: CGFloat
    var radius: CGFloat = Corner.md
    var notch: CGFloat = 7
    /// Пробитий корінець — подія минула: кругла дірка в корінці.
    var punched = false
    func path(in rect: CGRect) -> Path {
        var cuts = Path()
        func hole(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) { cuts.addEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)) }
        if vertical {
            let y = rect.maxY - stub
            hole(rect.minX, y, notch); hole(rect.maxX, y, notch)
            if punched { hole(rect.maxX - 18, rect.maxY - stub / 2, 5) }
        } else {
            let x = rect.maxX - stub
            hole(x, rect.minY, notch); hole(x, rect.maxY, notch)
            if punched { hole(rect.maxX - stub / 2, rect.minY + 16, 5) }
        }
        return Path(roundedRect: rect, cornerRadius: radius, style: .continuous).subtracting(cuts)
    }
}

/// Перфорація на лінії відриву: крапки кольору полотна, ніби дірочки наскрізь.
private struct Perforation: Shape {
    var vertical: Bool
    var stub: CGFloat
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset: CGFloat = 11
        if vertical {
            let y = rect.maxY - stub
            path.move(to: CGPoint(x: rect.minX + inset, y: y)); path.addLine(to: CGPoint(x: rect.maxX - inset, y: y))
        } else {
            let x = rect.maxX - stub
            path.move(to: CGPoint(x: x, y: rect.minY + inset)); path.addLine(to: CGPoint(x: x, y: rect.maxY - inset))
        }
        return path
    }
}

/// Квиток — головний предмет застосунку: основна частина на поверхні й корінець, залитий кольором жанру, за перфорацією.
/// Афішна подія — надрукований квиток із часом на корінці, зустріч від людей — квиток ще й з місцями. Обидві частини
/// тягнуться на висоту довшої, тож висоту задає вміст, а не місце виклику.
struct Ticket<Main: View, Stub: View>: View {
    var vertical = false
    let stubColor: Color
    /// Довжина корінця при стандартному тексті; з Dynamic Type росте разом із цифрами, до півтора раза.
    var stubLength: CGFloat = 84
    var radius: CGFloat = Corner.md
    var punched = false
    var surface: Color = Palette.surface
    /// Контур поверх квитка тією ж формою: пунктир порожнього квитка, рамка вибраного на мапі.
    var outline: (Color, StrokeStyle)? = nil
    @ViewBuilder let main: () -> Main
    @ViewBuilder let stub: () -> Stub
    @Environment(\.colorScheme) private var scheme
    @ScaledMetric(relativeTo: .title) private var textScale: CGFloat = 1
    private var length: CGFloat { stubLength * min(max(textScale, 1), 1.5) }
    var body: some View {
        let shape = TicketShape(vertical: vertical, stub: length, radius: radius, punched: punched)
        Group {
            if vertical {
                VStack(spacing: 0) {
                    main().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(surface)
                    stub().frame(maxWidth: .infinity).frame(height: length).background(stubColor)
                }
            } else {
                HStack(spacing: 0) {
                    main().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(surface)
                    stub().frame(width: length).frame(maxHeight: .infinity).background(stubColor)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .overlay {
            Perforation(vertical: vertical, stub: length)
                .stroke(Palette.canvas, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [0.1, 6]))
        }
        .clipShape(shape)
        .overlay { shape.stroke(Palette.hairline, lineWidth: scheme == .dark ? 1 : 0) }
        .overlay { if let outline { shape.stroke(outline.0, style: outline.1) } }
        .contentShape(shape)
    }
}

/// Друк корінця: велика година табличними цифрами, під нею день, а в зустрічі від людей — місця «3/8».
/// `row` — розкладка нижнього корінця вертикального квитка: година ліворуч, день і місця праворуч.
struct StubTime: View {
    let event: Event
    var compact = false
    var row = false
    var showsSeats = true
    /// Жанр словами над часом: колір корінця сам по собі нічого не каже, поки не підписаний. Малий корінець рядка його
    /// не друкує — там жанр стоїть текстом поруч.
    var showsGenre = true
    private var genre: String? {
        let name = categoryName(event.category)
        return showsGenre && !name.isEmpty ? name.uppercased() : nil
    }
    private var seats: String? {
        guard showsSeats, let room = event.gathering, !event.hasEnded(now: nowInstant()) else { return nil }
        return "\(room.attendeeCount)/\(room.capacity)"
    }
    private var label: String {
        var parts = [eventDate(event)]
        if let room = event.gathering, seats != nil { parts.append(Copy.attendees("\(room.attendeeCount)", "\(room.capacity)")) }
        return parts.joined(separator: ", ")
    }
    var body: some View {
        let parts = stubParts(event, compact: compact && !row, medium: row)
        let big = Text(parts.big).font(compact ? PoruchFont.numeralSmall : PoruchFont.numeral).monospacedDigit()
            .lineLimit(1).minimumScaleFactor(0.6)
        let small = Text(parts.small).font(PoruchFont.overline).kerning(0.6).lineLimit(1).minimumScaleFactor(0.7)
        let seatsLine = seats.map { seats in
            HStack(spacing: 3) {
                PoruchIcon(glyph: PoruchIcons.social, size: 12)
                Text(seats).font(PoruchFont.overline).monospacedDigit()
            }
        }
        let genreLine = genre.map { Text($0).font(row ? PoruchFont.overline : PoruchFont.stamp).kerning(0.6).lineLimit(1).minimumScaleFactor(0.6) }
        Group {
            if row {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: Space.sm) {
                        VStack(alignment: .leading, spacing: 2) { genreLine; big.fixedSize() }
                        Spacer(minLength: 0)
                        VStack(alignment: .trailing, spacing: 2) { small.fixedSize(); seatsLine }
                    }
                    HStack(alignment: .center, spacing: Space.sm) {
                        VStack(alignment: .leading, spacing: 0) { genreLine; big; small }
                        Spacer(minLength: 0)
                        seatsLine
                    }
                }
                .padding(.horizontal, Space.md)
                // Під цифрами години лишається порожнє місце нижніх виносних, і центрований друк прилипав жанром до
                // перфорації (4 зверху проти 12 знизу). Відступ зверху опускає його на 4 — видимі поля рівні.
                .padding(.top, Space.sm)
            } else {
                VStack(spacing: 2) {
                    genreLine?.padding(.bottom, Space.xs)
                    big
                    small
                    seatsLine?.padding(.top, Space.xs)
                }
                .padding(.horizontal, Space.sm)
            }
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}

/// Малий корінець у рядку списку: година й день на плитці кольору жанру з вирізами з боків. Стовпець корінців вирівнює
/// рядки, як розклад. Минулу подію пробито.
struct StubTile: View {
    let event: Event
    var size: CGFloat = 60
    /// Росте з текстом до 1,5×, як корінець квитка: на великому шрифті «18:00» стискалось до «18…».
    @ScaledMetric(relativeTo: .title) private var textScale: CGFloat = 1
    private var side: CGFloat { size * min(max(textScale, 1), 1.5) }
    var body: some View {
        StubTime(event: event, compact: true, showsSeats: false, showsGenre: false)
            .frame(width: side, height: side)
            .background(ticketStub(event))
            .clipShape(TicketShape(vertical: true, stub: side / 2, radius: Corner.sm, notch: 4))
            // Минулу подію пробито: дірка в куті плитки, а не через цифри.
            .overlay(alignment: .topTrailing) {
                if event.hasEnded(now: nowInstant()) { Circle().fill(Palette.canvas).frame(width: 9, height: 9).padding(6) }
            }
    }
}

/// Штамп стану на квитку: контур тоном і легкий нахил, як гумовий штамп на касі. На фото й корінці — білий по затемненню.
struct TicketStamp: View {
    let text: String
    var tone: BadgeTone = .neutral
    var glyph: PoruchGlyph?
    var onFill = false
    private var color: Color {
        if onFill { return .white }
        switch tone {
        case .success: return Palette.success
        case .accent: return Palette.accentText
        case .danger: return Palette.danger
        case .brand, .neutral: return Palette.inkSecondary
        }
    }
    var body: some View {
        HStack(spacing: 3) {
            if let glyph { PoruchIcon(glyph: glyph, size: 12) }
            Text(text.uppercased()).font(PoruchFont.stamp).kerning(0.8).lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .background { if onFill { RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.black.opacity(0.42)) } }
        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(color, lineWidth: 1.5))
        .rotationEffect(.degrees(-4))
    }
}
