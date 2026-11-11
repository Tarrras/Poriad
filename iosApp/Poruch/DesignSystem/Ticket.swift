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

/// Штрих перфорації: крапки кольору полотна на кроці 6.
private let perforation = StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [0.1, 6])

/// Лінія відриву поза квитком: та сама перфорація ділить поле «Коли» на день і годину. Завширшки зі штрих, лінія
/// посередині: вигляд нульової ширини SwiftUI не малює.
struct TearLine: View {
    var body: some View {
        Perforation(vertical: false, stub: 1.25).stroke(Palette.canvas, style: perforation).frame(width: 2.5)
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
        .overlay { Perforation(vertical: vertical, stub: length).stroke(Palette.canvas, style: perforation) }
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
        // Корінець росте лише до 1,5×, тож і друк на ньому — не більше: на AX5 «ЗАВТРА» й день обрізались. Повністю
        // дату читає VoiceOver і квиток поруч.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
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

/// Маленька ілюстрація з квитків замість сірої плитки з гліфом (10.11, «Папір»): там, де екран кличе до дії, а показати
/// ще нічого. Крихітні квитки тієї ж форми, корінці — кольорами жанрів; лише прикраса. `deck` — три вертикальні картки
/// віялом, як стос «Ваш тиждень»; `pair` — квиток і порожнє місце поруч: на подію ще ніхто не шукає компанію.
struct MiniTickets: View {
    enum Kind { case deck, pair }
    let kind: Kind
    let genres: [EventCategory]
    var side: CGFloat = 52

    /// Квиток-крихітка; без жанру — порожнє місце пунктиром.
    private func card(_ category: EventCategory?, width: CGFloat, height: CGFloat, vertical: Bool) -> some View {
        let stub = (vertical ? height : width) * 0.34
        let shape = TicketShape(vertical: vertical, stub: stub, radius: 3, notch: 1.5)
        return ZStack(alignment: vertical ? .bottom : .trailing) {
            if let category {
                Palette.surface
                categoryStub(category).frame(width: vertical ? nil : stub, height: vertical ? stub : nil)
            }
        }
        .frame(width: width, height: height)
        .clipShape(shape)
        .overlay {
            if category == nil { shape.stroke(Palette.inkTertiary.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [2.5, 2])) }
        }
        .shadow(color: category == nil ? .clear : Palette.shadowSpot, radius: 1.5, y: 0.5)
    }

    var body: some View {
        ZStack {
            switch kind {
            case .deck:
                let (width, height) = (side * 0.40, side * 0.56)
                let fan: [(Double, CGFloat, CGFloat)] = [(-14, -0.17, 0.03), (14, 0.17, 0.03), (0, 0, -0.02)]
                ForEach(Array(zip(genres, fan).enumerated()), id: \.offset) { _, item in
                    card(item.0, width: width, height: height, vertical: true)
                        .rotationEffect(.degrees(item.1.0)).offset(x: side * item.1.1, y: side * item.1.2)
                }
            case .pair:
                let (width, height) = (side * 0.60, side * 0.36)
                card(nil, width: width, height: height, vertical: false)
                    .rotationEffect(.degrees(7)).offset(x: side * 0.08, y: side * 0.15)
                card(genres.first, width: width, height: height, vertical: false)
                    .rotationEffect(.degrees(-8)).offset(x: -side * 0.07, y: -side * 0.11)
            }
        }
        .frame(width: side, height: side)
        .background(Palette.surfaceMuted, in: RoundedRectangle(cornerRadius: side > 44 ? Corner.sm : Corner.xs, style: .continuous))
        .decorative()
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

/// Штамп, що падає з розмаху (docs/design-wow-1.5.md, «Рух»): ×2.4 і −16° → удар ×0.92, −3° → ×1.04 → ×1, −4° за
/// 0,52 с, і важкий тактильний відгук саме в мить удару. Б'є лише на зміну `hit`, тож повторний показ стоїть спокійно.
/// «Зменшити рух» — проявляється в сталому масштабі, як «ЗБЕРЕЖЕНО» у стосі.
struct StampDrop: View {
    let stamp: TicketStamp
    let hit: Int
    /// Удар уже чекає (`hit` зміниться наступним оновленням): до нього штамп прозорий, а не кадр у спокої перед ×2.4.
    var armed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var impact = 0

    var body: some View {
        // Кути — поверх власних −4° штампа.
        let still = reduceMotion
        stamp
            .keyframeAnimator(initialValue: StampPose(), trigger: hit) { content, pose in
                content.scaleEffect(pose.scale).rotationEffect(.degrees(pose.turn)).opacity(armed ? 0 : pose.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    MoveKeyframe(still ? 1 : 2.4)
                    LinearKeyframe(still ? 1 : 0.92, duration: 0.234, timingCurve: stampSwing)
                    LinearKeyframe(still ? 1 : 1.04, duration: 0.14, timingCurve: stampRebound)
                    LinearKeyframe(1, duration: 0.146, timingCurve: stampRebound)
                }
                KeyframeTrack(\.turn) {
                    MoveKeyframe(still ? 0 : -12)
                    LinearKeyframe(still ? 0 : 1, duration: 0.234, timingCurve: stampSwing)
                    LinearKeyframe(still ? 0 : -0.5, duration: 0.14, timingCurve: stampRebound)
                    LinearKeyframe(0, duration: 0.146, timingCurve: stampRebound)
                }
                KeyframeTrack(\.opacity) {
                    MoveKeyframe(0)
                    LinearKeyframe(1, duration: 0.234, timingCurve: stampSwing)
                }
            }
            .sensoryFeedback(.impact(weight: .heavy), trigger: impact)
            .onChange(of: hit) { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + (still ? 0 : 0.234)) { impact += 1 }
            }
    }
}

private struct StampPose {
    var scale: CGFloat = 1
    var turn: Double = 0
    var opacity: Double = 1
}

/// Розгін до удару й відскок — ті самі криві, що на сайті (`cubic-bezier(.55, 0, .9, .45)` і `(.2, .8, .3, 1)`).
private let stampSwing = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.55, y: 0), endControlPoint: UnitPoint(x: 0.9, y: 0.45))
private let stampRebound = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.2, y: 0.8), endControlPoint: UnitPoint(x: 0.3, y: 1))
