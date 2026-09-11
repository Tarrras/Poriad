import SwiftUI
import Shared

/// Design tokens for «Поруч». The single source of truth is docs/design-system.md; the Android
/// counterpart lives in androidApp/.../ui/Tokens.kt and carries the same values.

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255, alpha: 1
        )
    }
}

extension Color {
    /// Resolves per trait collection so every token follows the viewer's appearance. The alphas
    /// are per-appearance too: shadows exist on paper and are switched off on a black canvas.
    init(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) {
        self.init(UIColor {
            $0.userInterfaceStyle == .dark
                ? UIColor(rgb: dark).withAlphaComponent(darkAlpha)
                : UIColor(rgb: light).withAlphaComponent(lightAlpha)
        })
    }
}

/// Mixes two packed colours; used to light a pastel from the top and to tint a shadow.
private func blend(_ a: UInt32, _ b: UInt32, _ t: CGFloat) -> UIColor {
    func channel(_ value: UInt32, _ shift: UInt32) -> CGFloat { CGFloat((value >> shift) & 0xFF) / 255 }
    return UIColor(
        red: channel(a, 16) + (channel(b, 16) - channel(a, 16)) * t,
        green: channel(a, 8) + (channel(b, 8) - channel(a, 8)) * t,
        blue: channel(a, 0) + (channel(b, 0) - channel(a, 0)) * t,
        alpha: 1
    )
}

/// Warm paper ground, white cards lifted off it, near-black actions — Corner with volume.
enum Palette {
    static let brand = Color(light: 0x14130F, dark: 0xF5F3EE)
    static let brandPressed = Color(light: 0x32302A, dark: 0xD9D6CE)
    static let brandContainer = Color(light: 0xEAE7DE, dark: 0x2A2823)
    static let onBrandContainer = Color(light: 0x14130F, dark: 0xF5F3EE)
    static let onBrand = Color(light: 0xFBFAF7, dark: 0x14130F)

    static let accent = Color(light: 0xD9603A, dark: 0xEE8B63)
    static let accentContainer = Color(light: 0xFBE7DE, dark: 0x40251A)
    static let onAccentContainer = Color(light: 0x7A2E14, dark: 0xFBDACB)

    static let success = Color(light: 0x2F7D4F, dark: 0x5CBF85)
    static let successContainer = Color(light: 0xDFF0E3, dark: 0x17301F)
    static let onSuccessContainer = Color(light: 0x1B4C2F, dark: 0xBFE8CD)

    static let danger = Color(light: 0xB3402B, dark: 0xE9705A)
    static let dangerContainer = Color(light: 0xF8E1DC, dark: 0x3A1A15)

    static let ink = Color(light: 0x14130F, dark: 0xF5F3EE)
    static let inkSecondary = Color(light: 0x6B675E, dark: 0xA8A398)
    static let inkTertiary = Color(light: 0x9A958A, dark: 0x7C776C)

    static let surface = Color(light: 0xFFFFFF, dark: 0x1F1E1B)
    /// A card that floats needs to *look* nearer; on a black canvas only a lighter fill does that.
    static let surfaceRaised = Color(light: 0xFFFFFF, dark: 0x272521)
    static let surfaceMuted = Color(light: 0xEDEBE4, dark: 0x2C2A25)
    static let canvas = Color(light: 0xF2F0EA, dark: 0x121110)
    static let canvasTint = Color(light: 0xEAE6DA, dark: 0x1B1A17)

    /// Warm light at the top of a screen header, fading into paper.
    static let heroTop = Color(light: 0xF4E7D8, dark: 0x272119)
    static let heroBottom = Color(light: 0xF2F0EA, dark: 0x121110)

    /// Shadows are brown-black, not neutral: a grey shadow on warm paper reads as dirt. Dark mode
    /// zeroes their alpha rather than their radius — there is no paper left to cast onto.
    static let shadowSpot = Color(light: 0x2A2016, dark: 0x000000, lightAlpha: 0.20, darkAlpha: 0)
    static let shadowAmbient = Color(light: 0x2A2016, dark: 0x000000, lightAlpha: 0.10, darkAlpha: 0)

    static let hairline = Color(light: 0xE5E1D6, dark: 0x33302B)
}

/// Every category owns a deep hue for glyphs and text, plus a pastel wash for tiles and pins.
private let categoryHues: [String: UInt32] = [
    "music": 0x6D4AC9, "sport": 0x0F7F73, "art": 0xC43B6B, "food": 0xC96A1E,
    "games": 0x2F63C4, "outdoors": 0x3E7D3A, "social": 0xB8562F,
    // Золото: єдина вільна ділянка палітри між помаранчевим «їжею» і рожевим «мистецтвом».
    // Палітру будували на сім категорій. Тепер їх девʼять, і два останні відтінки —
    // золото для стендапу й бірюза для дитячого — підібрані вручну за контрастом, а не
    // виведені з системи. Обидва варті погляду дизайнера при перегляді палітри.
    "comedy": 0xA07813,
    "kids": 0x1F8A8A
]
private let categoryWashes: [String: UInt32] = [
    "music": 0xEBE4FB, "sport": 0xDDF0EC, "art": 0xFBE1EA, "food": 0xFBEBD9,
    "games": 0xE1EAFB, "outdoors": 0xE4F1E2, "social": 0xFAE5DA, "comedy": 0xF7ECD2, "kids": 0xD9EFEF
]

func categoryColor(_ category: String) -> Color {
    guard let hue = categoryHues[category] else { return Palette.inkSecondary }
    return Color(light: hue, dark: hue)
}

func categoryUIColor(_ category: String) -> UIColor { UIColor(rgb: categoryHues[category] ?? 0x6B675E) }

/**
 The map is drawn from the palette rather than from a hosted style, so the ground under the pins is
 the paper the cards sit on and the roads are the surface they are printed with. A token is a
 dynamic colour and MapLibre wants hex, so each one is resolved for the appearance being drawn.
 */
func mapTokens(_ scheme: ColorScheme) -> MapTokens {
    let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
    func hex(_ color: Color) -> String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(
            format: "#%02X%02X%02X",
            Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded())
        )
    }
    return MapTokens(
        canvas: hex(Palette.canvas), canvasTint: hex(Palette.canvasTint), surface: hex(Palette.surface),
        surfaceMuted: hex(Palette.surfaceMuted), hairline: hex(Palette.hairline), ink: hex(Palette.ink),
        inkSecondary: hex(Palette.inkSecondary), inkTertiary: hex(Palette.inkTertiary), dark: scheme == .dark
    )
}

/**
 The category hue as *text and glyph* colour. The deep hue is mixed for warm paper; on a near black
 surface the same value falls to about 2.5:1, so dark mode lifts it toward white until it clears
 the 4.5:1 the design system promises. `categoryColor` stays the raw hue — it is what map pins and
 washes are built from, where the hue sits on its own light ground.
 */
func categoryInk(_ category: String) -> Color {
    guard let hue = categoryHues[category] else { return Palette.inkSecondary }
    return Color(UIColor { $0.userInterfaceStyle == .dark ? blend(hue, 0xFFFFFF, 0.45) : UIColor(rgb: hue) })
}

/// Second hue of the pair: the neighbour a category leans on when its cover needs two stops.
private let categoryPartners: [String: UInt32] = [
    "music": 0xC43B6B, "sport": 0x2F63C4, "art": 0x6D4AC9, "food": 0xC43B6B,
    "games": 0x0F7F73, "outdoors": 0x0F7F73, "social": 0xC96A1E, "comedy": 0xC43B6B, "kids": 0x2F63C4
]

/**
 Cover fill for a category: a lit pastel in light mode, a low veil in dark. Two hues rather than
 one — the pair keeps a wall of covers from reading as a single tinted block, and the light corner
 makes a photoless card read as a surface rather than a swatch.
 */
func categoryGradient(_ category: String) -> LinearGradient {
    let hue = categoryHues[category] ?? 0x6B675E
    let partner = categoryPartners[category] ?? hue
    let wash = categoryWashes[category] ?? 0xEDEBE4
    let stops = [
        Color(UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(rgb: hue).withAlphaComponent(0.30) : blend(wash, 0xFFFFFF, 0.55) }),
        Color(UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(rgb: hue).withAlphaComponent(0.20) : UIColor(rgb: wash) }),
        Color(UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(rgb: partner).withAlphaComponent(0.14) : blend(wash, partner, 0.22) })
    ]
    return LinearGradient(colors: stops, startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// Header wash: warm light at the top of the screen, paper at the bottom.
let heroGradient = LinearGradient(colors: [Palette.heroTop, Palette.heroBottom], startPoint: .top, endPoint: .bottom)

/// The primary action is a solid of ink, lifted by a hair of light along its top edge.
let brandGradient = LinearGradient(
    colors: [
        Color(UIColor { $0.userInterfaceStyle == .dark ? blend(0xF5F3EE, 0xFFFFFF, 0.22) : blend(0x14130F, 0x4A463D, 0.22) }),
        Palette.brand
    ],
    startPoint: .top, endPoint: .bottom
)

/// A tone laid over its own container: badges and glyph tiles read as filled objects, not patches.
func toneGradient(_ container: Color, _ tone: Color) -> LinearGradient {
    LinearGradient(colors: [container, tone.opacity(0.16)], startPoint: .top, endPoint: .bottom)
}

/// Pastel in light mode; in dark the same hue is dropped to a low-alpha veil over the surface.
func categoryWash(_ category: String) -> Color {
    guard let wash = categoryWashes[category], let hue = categoryHues[category] else { return Palette.surfaceMuted }
    return Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: hue).withAlphaComponent(0.22) : UIColor(rgb: wash) })
}

/**
 Two voices, not one weight scale.

 The grotesque carries names, actions and data; large sizes get negative tracking so a heading
 reads as one shape rather than a row of letters. The serif carries the one line that says *what a
 thing is* — `descriptor` under a place name, `lead` at the top of a detail screen. That is the
 Corner move: a change of voice separates description from label without a fourth weight of the
 same face.

 Both are system faces (SF Pro and New York), so both scale with Dynamic Type and both ship with
 the Cyrillic the app is written in.
 */
enum PoruchFont {
    static let display = Font.system(size: 32, weight: .bold)
    static let title1 = Font.system(size: 26, weight: .bold)
    static let title2 = Font.system(size: 19, weight: .bold)
    static let title3 = Font.system(size: 16, weight: .semibold)
    /// A section is announced lowercase at reading size — caps stay where they carry data.
    static let sectionTitle = Font.system(size: 17, weight: .bold)
    /// Card names are set in caps, the way Corner sets place names.
    static let cardName = Font.system(size: 15, weight: .bold)
    static let bodyText = Font.system(size: 15)
    static let subhead = Font.system(size: 14)
    static let caption = Font.system(size: 13)
    static let label = Font.system(size: 13, weight: .medium)
    static let button = Font.system(size: 15, weight: .semibold)
    static let overline = Font.system(size: 11, weight: .bold)
    /// The serif italic Corner sets under a place name.
    static let descriptor = Font.system(size: 14, design: .serif).italic()
    /// The same serif, upright: the lead paragraph of a detail screen.
    static let lead = Font.system(size: 16, design: .serif)
}

/// Tracking that belongs to a size, not to a call site: large type tightens, small caps open up.
extension View {
    func displayTracking() -> some View { kerning(-0.8) }
    func titleTracking() -> some View { kerning(-0.6) }
}

enum Space {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let section: CGFloat = 32
    static let page: CGFloat = 16
}

enum Corner {
    static let xs: CGFloat = 10
    static let sm: CGFloat = 14
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 26
}

/**
 Four steps, and each one means a distance from the paper: a card rests on it, a chip hovers, the
 tab bar and the map carousel float over content. Dark mode keeps the numbers and loses the
 shadows — `Palette.shadow*` are transparent there — and steps the surface up instead.
 */
enum Elevation {
    static let flat: CGFloat = 0
    static let card: CGFloat = 4
    static let raised: CGFloat = 10
    static let overlay: CGFloat = 20
}

extension View {
    /**
     Two shadows make an object: a tight one that draws the contact edge and a wide one that reads
     as the distance to the ground. One shadow at this radius looks like a blur; two look like a
     thing sitting on paper.

     `tint` lets an action cast its own colour — an ink button glows warm, a category tile glows in
     its own hue — instead of every element smudging the page with the same grey.
     */
    func lifted(_ elevation: CGFloat, tint: Color? = nil) -> some View {
        shadow(color: tint ?? Palette.shadowSpot, radius: elevation / 3, y: elevation / 8)
            .shadow(color: tint?.opacity(0.5) ?? Palette.shadowAmbient, radius: elevation, y: elevation / 2.5)
    }
}

/// Card and panel elevation: two shadows on paper, a raised surface and a hairline in the dark.
struct CardSurface: ViewModifier {
    var radius: CGFloat = Corner.lg
    var elevation: CGFloat = Elevation.card
    func body(content: Content) -> some View {
        content
            .background(
                elevation >= Elevation.raised ? Palette.surfaceRaised : Palette.surface,
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    // A lit card needs less line to hold it; a flat one still needs the full hairline.
                    .strokeBorder(Palette.hairline.opacity(elevation > 0 ? 0.55 : 1), lineWidth: 1)
            )
            .lifted(elevation)
    }
}

/**
 Tap feedback with depth: the surface dips a fraction under the finger and springs back. Paired
 with the card shadow this is what makes a card feel like an object rather than a rectangle, so
 every tappable surface uses it instead of `.plain`. Reduced motion drops the dip.
 */
struct PressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var pressedScale: CGFloat = 0.98
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? pressedScale : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension View {
    func cardSurface(radius: CGFloat = Corner.lg, elevation: CGFloat = Elevation.card) -> some View {
        modifier(CardSurface(radius: radius, elevation: elevation))
    }
    /// Photos carry no information the title does not, so they stay out of the accessibility tree.
    func decorative() -> some View { accessibilityHidden(true) }
}

// ---------------------------------------------------------------- event formatting

let categories: [(String, String, String)] = [
    ("music", "Музика", "music.note"), ("sport", "Спорт", "figure.run"), ("art", "Мистецтво", "paintpalette"),
    ("food", "Їжа", "fork.knife"), ("games", "Ігри", "dice"), ("outdoors", "Природа", "leaf"),
    ("social", "Зустрічі", "person.2"), ("comedy", "Стендап", "mic"), ("kids", "Дітям", "balloon.2")
]

func categoryName(_ key: String) -> String { categories.first { $0.0 == key }?.1 ?? key }
func categorySymbol(_ key: String) -> String { categories.first { $0.0 == key }?.2 ?? "mappin" }

/// The app's own glyph for a category, twin to `categoryIcon` on Android.
func categoryGlyph(_ key: String) -> PoruchGlyph {
    switch key {
    case "music": PoruchIcons.music
    case "sport": PoruchIcons.sport
    case "art": PoruchIcons.art
    case "food": PoruchIcons.food
    case "games": PoruchIcons.games
    case "outdoors": PoruchIcons.outdoors
    case "comedy": PoruchIcons.comedy
    case "kids": PoruchIcons.kids
    default: PoruchIcons.social
    }
}

/**
 Розбір і форматування дат — по одному об'єкту на пару «пояс + шаблон», а не по одному на картку.

 `DateFormatter` та `ISO8601DateFormatter` дорогі саме у створенні: за ними стоїть ICU, локаль і
 календар. Поки вони робилися всередині `eventOverline`, кожен рядок списку платив за три-чотири
 такі створення — а список перебудовує рядки на кожному кроці скролу. Це і є та частина фрізу, яку
 не видно в жодному профілі як «моя функція»: час іде в Foundation.

 Обидва парсери налаштовані один раз і далі не змінюються, тож ділити їх між потоками безпечно —
 а `EventReminders` справді розбирає дати з фонового колбека. Словники ж захищені замком: його
 вартість — наносекунди проти сотень мікросекунд на створення форматера, а неспівпадіння тут
 коштувало б не глюка, а падіння.
 */
private let isoParser: ISO8601DateFormatter = ISO8601DateFormatter()
private let isoParserWithFraction: ISO8601DateFormatter = {
    let parser = ISO8601DateFormatter()
    parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return parser
}()

func parseEventDate(_ value: String) -> Date? {
    if let date = isoParser.date(from: value) { return date }
    return isoParserWithFraction.date(from: value)
}

private let formatterLock = NSLock()
private var formatters: [String: DateFormatter] = [:]
private var calendars: [String: Calendar] = [:]

private func formatter(_ event: Event, _ pattern: String) -> DateFormatter {
    let key = event.timeZone + "|" + pattern
    formatterLock.lock()
    defer { formatterLock.unlock() }
    if let cached = formatters[key] { return cached }
    let formatter = DateFormatter()
    formatter.locale = ukrainian
    formatter.timeZone = TimeZone(identifier: event.timeZone)
    formatter.dateFormat = pattern
    formatters[key] = formatter
    return formatter
}

/// Календар теж не безкоштовний: за ним свій пояс і локаль, а `dayLabel` питає його по чотири
/// рази на картку.
private func calendar(_ event: Event) -> Calendar {
    let zone = event.timeZone
    formatterLock.lock()
    defer { formatterLock.unlock() }
    if let cached = calendars[zone] { return cached }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone) ?? .current
    calendar.locale = ukrainian
    calendars[zone] = calendar
    return calendar
}

/// «Зараз» у тому вигляді, якого чекає спільна логіка. Домен свідомо приймає час параметром,
/// а не читає годинник сам, тож міст будуємо тут.
private func nowInstant() -> KotlinInstant {
    KotlinInstant.companion.fromEpochMilliseconds(
        epochMilliseconds: Int64(Date().timeIntervalSince1970 * 1000))
}

private let ukrainian = Locale(identifier: "uk_UA")

/// «У суботу о 18:00»: знахідний відмінок, бо називний тут читається як список, а не як речення.
private let weekdayOn = ["У неділю", "У понеділок", "У вівторок", "У середу",
                         "У четвер", "У п\u{2019}ятницю", "У суботу"]

/// Наскільки подія далеко, у словах, якими це формулює людина.
///
/// «13 березня» саме по собі — пастка: за пів року це читається як березень, що вже минув.
/// Тому все, що поза поточним роком, несе рік.
private func dayLabel(_ event: Event, _ date: Date, short: Bool) -> String {
    let calendar = calendar(event)
    let now = Date()

    if calendar.isDateInToday(date) { return "Сьогодні" }
    if calendar.isDateInTomorrow(date) { return "Завтра" }

    let days = calendar.dateComponents([.day],
                                       from: calendar.startOfDay(for: now),
                                       to: calendar.startOfDay(for: date)).day ?? 0
    // За тиждень назва дня ще орієнтує, далі вже ні — там потрібна дата.
    if days >= 2, days <= 6 {
        return weekdayOn[calendar.component(.weekday, from: date) - 1]
    }
    let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
    let pattern: String
    if short {
        pattern = sameYear ? "EEE, d MMM" : "EEE, d MMM yyyy"
    } else {
        pattern = sameYear ? "EEEE, d MMMM" : "d MMMM yyyy"
    }
    return formatter(event, pattern).string(from: date)
}

/// Overline above a card title: «СЬОГОДНІ · 18:30», «СБ, 13 БЕР. 2027 · 18:00». Event's own zone.
func eventOverline(_ event: Event) -> String {
    guard let date = parseEventDate(event.startsAt) else { return event.startsAt }
    if event.isUnderway(now: nowInstant()) { return "ТРИВАЄ ЗАРАЗ" }
    let hour = formatter(event, "HH:mm").string(from: date)
    return "\(dayLabel(event, date, short: true)) · \(hour)".uppercased(with: ukrainian)
}

/// Long form for the detail screen. The zone is named only when it differs from the reader's own:
/// for someone in Kyiv reading about Kyiv, «GMT+03:00» is noise, but for a traveller it is the
/// difference between arriving and missing it.
func eventDate(_ event: Event) -> String {
    guard let date = parseEventDate(event.startsAt) else { return event.startsAt }
    let hour = formatter(event, "HH:mm").string(from: date)
    let eventZone = TimeZone(identifier: event.timeZone) ?? .current
    let zoneSuffix = eventZone.secondsFromGMT(for: date) == TimeZone.current.secondsFromGMT(for: date)
        ? "" : " " + formatter(event, "z").string(from: date)
    let prefix = event.isUnderway(now: nowInstant()) ? "Триває зараз · " : ""
    return "\(prefix)\(dayLabel(event, date, short: false)) · \(hour)\(zoneSuffix)"
}


/// True once the remaining capacity is small enough to be worth an urgency badge.
///
/// Поріг рахує домен (`Gathering.isScarce`) — раніше та сама формула жила двома копіями, тут і в
/// Android. Афіша сюди не потрапляє взагалі: місткості в неї немає, а отже й терміновості.
func eventScarce(_ event: Event) -> Bool {
    guard let room = event.gathering, !event.isCancelled else { return false }
    return room.isScarce
}

/// Ціна квитка одним рядком. «Безкоштовно», «від стількох» і «джерело не сказало» — три різні
/// відповіді, і зливати останню з першою означало б назвати платну подію дармовою.
func listingPrice(_ listing: Listing) -> String {
    if listing.isFree?.boolValue == true { return "Безкоштовно" }
    guard let price = listing.priceMin?.doubleValue else { return "Ціну вкаже джерело" }
    let amount = price == price.rounded() ? String(Int(price)) : String(format: "%.2f", price)
    return "від \(amount) ₴"
}
