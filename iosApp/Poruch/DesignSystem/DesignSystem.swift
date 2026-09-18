import SwiftUI
import Shared

/// Токени дизайну. Джерело правди — docs/design-system.md; ті самі значення в androidApp/.../ui/Tokens.kt.

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255, alpha: 1
        )
    }
}

extension Color {
    /// Динамічний колір за темою. Альфа теж per-theme: тіні є на папері й вимкнені на чорному.
    init(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) {
        self.init(UIColor {
            $0.userInterfaceStyle == .dark
                ? UIColor(rgb: dark).withAlphaComponent(darkAlpha)
                : UIColor(rgb: light).withAlphaComponent(lightAlpha)
        })
    }
}

/// Змішує два кольори: підсвітити пастель згори, тонувати тінь.
private func blend(_ a: UInt32, _ b: UInt32, _ t: CGFloat) -> UIColor {
    func channel(_ value: UInt32, _ shift: UInt32) -> CGFloat { CGFloat((value >> shift) & 0xFF) / 255 }
    return UIColor(
        red: channel(a, 16) + (channel(b, 16) - channel(a, 16)) * t,
        green: channel(a, 8) + (channel(b, 8) - channel(a, 8)) * t,
        blue: channel(a, 0) + (channel(b, 0) - channel(a, 0)) * t,
        alpha: 1
    )
}

/// Світла тема — прохолодний сірий фон і білі картки без рамок (Apple Store); темна — майже
/// чорне полотно й напівпрозорі картки з тонкою світлою лінією (Moonly). Дії майже чорні / білі.
enum Palette {
    static let brand = Color(light: 0x1D1D1F, dark: 0xF5F5F7)
    static let brandPressed = Color(light: 0x3A3A3C, dark: 0xD1D1D6)
    static let brandContainer = Color(light: 0xE8E8ED, dark: 0x2C2C33)
    static let onBrandContainer = Color(light: 0x1D1D1F, dark: 0xF5F5F7)
    static let onBrand = Color(light: 0xFFFFFF, dark: 0x1D1D1F)

    static let accent = Color(light: 0xE0582F, dark: 0xFF8A5B)
    static let accentContainer = Color(light: 0xFDE7DF, dark: 0x3F2419)
    static let onAccentContainer = Color(light: 0x7A2E14, dark: 0xFFD9C8)

    static let success = Color(light: 0x2E7D4F, dark: 0x5DC389)
    static let successContainer = Color(light: 0xDFF3E6, dark: 0x16311F)
    static let onSuccessContainer = Color(light: 0x1B4C2F, dark: 0xBFEBD0)

    static let danger = Color(light: 0xC0392B, dark: 0xFF6B5B)
    static let dangerContainer = Color(light: 0xFBE3E0, dark: 0x3C1A16)

    static let ink = Color(light: 0x1D1D1F, dark: 0xF5F5F7)
    static let inkSecondary = Color(light: 0x6E6E73, dark: 0xA1A1A8)
    static let inkTertiary = Color(light: 0x98989D, dark: 0x6E6E76)

    static let surface = Color(light: 0xFFFFFF, dark: 0x17171C)
    /// Те, що плаває над темним полотном, світліше за картку в потоці.
    static let surfaceRaised = Color(light: 0xFFFFFF, dark: 0x202027)
    static let surfaceMuted = Color(light: 0xF2F2F7, dark: 0x26262E)
    static let canvas = Color(light: 0xF5F5F7, dark: 0x0B0B0F)
    static let canvasTint = Color(light: 0xEBEBF0, dark: 0x141419)

    /// Шапка тепер того ж тону, що й полотно: екран — один спокійний аркуш.
    static let heroTop = Color(light: 0xF5F5F7, dark: 0x0B0B0F)
    static let heroBottom = Color(light: 0xF5F5F7, dark: 0x0B0B0F)

    /// Тінь є лише в того, що плаває (таббар, карусель): мʼяка, нейтральна, майже непомітна.
    static let shadowSpot = Color(light: 0x000000, dark: 0x000000, lightAlpha: 0.10, darkAlpha: 0.40)
    static let shadowAmbient = Color(light: 0x000000, dark: 0x000000, lightAlpha: 0.06, darkAlpha: 0.30)

    /// Розділювачі у світлій темі; у темній — ще й край картки.
    static let hairline = Color(light: 0xE5E5EA, dark: 0x2A2A33)
}

/// Глибокий відтінок категорії для гліфів і тексту; пастель для плиток і пінів робиться з нього.
private let categoryHues: [String: UInt32] = [
    "music": 0x6D4AC9, "sport": 0x0F7F73, "art": 0xC43B6B, "food": 0xC96A1E,
    "games": 0x2F63C4, "outdoors": 0x3E7D3A, "social": 0xB8562F,
    // Палітру будували на сім категорій. Золото й бірюза підібрані вручну за контрастом,
    // варті погляду дизайнера.
    "comedy": 0xA07813,
    "kids": 0x1F8A8A,
    // Олива й пурпур — середини найбільших вільних проміжків на колі відтінків.
    "tours": 0x5F7F1F,
    "conference": 0x933FA8
]
private let categoryWashes: [String: UInt32] = [
    "music": 0xEBE4FB, "sport": 0xDDF0EC, "art": 0xFBE1EA, "food": 0xFBEBD9,
    "games": 0xE1EAFB, "outdoors": 0xE4F1E2, "social": 0xFAE5DA, "comedy": 0xF7ECD2, "kids": 0xD9EFEF,
    "tours": 0xECF0E4, "conference": 0xF2E8F5
]

func categoryColor(_ category: String) -> Color {
    guard let hue = categoryHues[category] else { return Palette.inkSecondary }
    return Color(light: hue, dark: hue)
}

func categoryUIColor(_ category: String) -> UIColor { UIColor(rgb: categoryHues[category] ?? 0x6B675E) }

/// Токени палітри для стилю мапи. MapLibre хоче hex, тому кожен резолвиться під поточну тему.
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

/// Відтінок категорії для тексту й гліфів. У темній темі освітлюється до контрасту 4.5:1.
/// `categoryColor` лишається сирим відтінком для пінів і заливок.
func categoryInk(_ category: String) -> Color {
    guard let hue = categoryHues[category] else { return Palette.inkSecondary }
    return Color(UIColor { $0.userInterfaceStyle == .dark ? blend(hue, 0xFFFFFF, 0.45) : UIColor(rgb: hue) })
}

/// Другий відтінок пари для градієнта обкладинки.
private let categoryPartners: [String: UInt32] = [
    "music": 0xC43B6B, "sport": 0x2F63C4, "art": 0x6D4AC9, "food": 0xC43B6B,
    "games": 0x0F7F73, "outdoors": 0x0F7F73, "social": 0xC96A1E, "comedy": 0xC43B6B, "kids": 0x2F63C4,
    "tours": 0x3E7D3A, "conference": 0x6D4AC9
]

/// Заливка обкладинки: пастель у світлій темі, тонка вуаль у темній. Два відтінки, щоб стіна обкладинок не зливалась.
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

/// Заливка шапки: тепле світло вгорі, папір унизу.
let heroGradient = LinearGradient(colors: [Palette.heroTop, Palette.heroBottom], startPoint: .top, endPoint: .bottom)

/// Головна дія: рівна заливка чорнилом. Градієнт лишився типом, щоб місця виклику не змінювались.
let brandGradient = LinearGradient(colors: [Palette.brand, Palette.brand], startPoint: .top, endPoint: .bottom)

/// Бейдж — рівна заливка контейнера. Градієнт лишився типом, щоб місця виклику не змінювались.
func toneGradient(_ container: Color, _ tone: Color) -> LinearGradient {
    LinearGradient(colors: [container, container], startPoint: .top, endPoint: .bottom)
}

/// Пастель у світлій темі; у темній той самий відтінок як вуаль з низькою альфою.
func categoryWash(_ category: String) -> Color {
    guard let wash = categoryWashes[category], let hue = categoryHues[category] else { return Palette.surfaceMuted }
    return Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: hue).withAlphaComponent(0.22) : UIColor(rgb: wash) })
}

/// Один голос — SF Pro. Ієрархію несуть кегль і вага, а не зміна гарнітури чи регістру.
enum PoruchFont {
    static let display = Font.system(size: 34, weight: .bold)
    static let title1 = Font.system(size: 28, weight: .bold)
    static let title2 = Font.system(size: 22, weight: .bold)
    static let title3 = Font.system(size: 17, weight: .semibold)
    /// Заголовок секції великий і жирний, як «Discover what's new».
    static let sectionTitle = Font.system(size: 22, weight: .bold)
    /// Назва картки звичайним регістром.
    static let cardName = Font.system(size: 17, weight: .semibold)
    static let bodyText = Font.system(size: 16)
    static let subhead = Font.system(size: 15)
    static let caption = Font.system(size: 13)
    static let label = Font.system(size: 14, weight: .medium)
    static let button = Font.system(size: 16, weight: .semibold)
    static let overline = Font.system(size: 11, weight: .semibold)
    /// Категорія під назвою: той самий гротеск, кольором категорії.
    static let descriptor = Font.system(size: 13, weight: .medium)
    /// Лід на екрані деталей.
    static let lead = Font.system(size: 17)
}

/// Трекінг за розміром: великий текст стискається в одну форму.
extension View {
    func displayTracking() -> some View { kerning(-1.0) }
    func titleTracking() -> some View { kerning(-0.7) }
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
    static let xs: CGFloat = 12
    static let sm: CGFloat = 14
    static let md: CGFloat = 18
    static let lg: CGFloat = 24
    static let xl: CGFloat = 28
}

/// Два рівні: усе в потоці лежить пласко (`card` = 0, картку робить лише різниця тону
/// з полотном); плаває тільки те, що справді над екраном — таббар, карусель, банер.
enum Elevation {
    static let flat: CGFloat = 0
    static let card: CGFloat = 0
    static let raised: CGFloat = 8
    static let overlay: CGFloat = 24
}

extension View {
    /// Одна мʼяка тінь, широка й бліда. Нуль — без тіні. `tint` фарбує її кольором обʼєкта.
    @ViewBuilder func lifted(_ elevation: CGFloat, tint: Color? = nil) -> some View {
        if elevation > 0 {
            shadow(color: tint ?? Palette.shadowSpot, radius: elevation, y: elevation / 3)
        } else { self }
    }
}

/// Картка: біла на сірому без рамки; у темряві — трохи світліша за полотно, з тонкою лінією по краю.
struct CardSurface: ViewModifier {
    var radius: CGFloat = Corner.lg
    var elevation: CGFloat = Elevation.card
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            .background(
                elevation >= Elevation.raised ? Palette.surfaceRaised : Palette.surface,
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: scheme == .dark ? 1 : 0)
            )
            .lifted(elevation)
    }
}

/// Скло під тим, що плаває над вмістом: таббар, карусель мапи. Розмиває те, що проїжджає під ним.
struct GlassSurface: ViewModifier {
    var radius: CGFloat = Corner.xl
    /// Тінь під склом просвічує крізь нього. Над однорідним тлом це непомітно, над мапою — сіра пляма.
    /// `false` лишає мʼяку тінь лише назовні від форми: опора є, а всередину скла нічого не потрапляє.
    var shadow = true
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .background(Palette.surface.opacity(scheme == .dark ? 0.55 : 0.6), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(scheme == .dark ? Palette.hairline : Color.white.opacity(0.6), lineWidth: 1)
            )
            .background { if !shadow { OuterShadow(radius: radius) } }
            .lifted(shadow ? Elevation.overlay : 0)
    }
}

/// Тінь лише назовні від скругленого прямокутника: з шару тіні вирізано саму форму.
private struct OuterShadow: View {
    let radius: CGFloat
    /// Наскільки тінь виходить за форму; маска має її вміщати.
    private let reach: CGFloat = 28
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape.fill(Color.black)
            .shadow(color: Palette.shadowSpot, radius: 12, y: 4)
            .mask {
                Rectangle().padding(-reach)
                    .overlay { shape.blendMode(.destinationOut) }
                    .compositingGroup()
            }
            .allowsHitTesting(false)
    }
}

/// Відгук на тап: поверхня трохи просідає і повертається. Усі натискні поверхні беруть його замість `.plain`.
/// Reduced motion прибирає просідання.
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
    func glassSurface(radius: CGFloat = Corner.xl, shadow: Bool = true) -> some View { modifier(GlassSurface(radius: radius, shadow: shadow)) }
    /// Фото не додає нічого до назви, тому поза деревом доступності.
    func decorative() -> some View { accessibilityHidden(true) }
}

/// Поля горизонтальної стрічки всередині смуги прокрутки, як `contentPadding` у Compose `LazyRow`:
/// елементи зникають на краю екрана, а не за 16 pt до нього. Смуга має йти від краю до краю,
/// тож поля сторінки знімають від'ємним відступом на місці виклику. `spread` — запас на тінь,
/// щоб смуга не обрізала її; ззовні він компенсується.
extension View {
    func railContentPadding(_ inset: CGFloat = Space.page, spread: CGFloat = Space.sm) -> some View {
        contentMargins(.horizontal, inset, for: .scrollContent)
            .contentMargins(.vertical, spread, for: .scrollContent)
            .padding(.vertical, -spread)
    }
}

/// Висота смуги статусу з вікна, а не з `GeometryReader`: обгортка ламала горизонтальний скрол
/// стрічок. Питати вікно з `body` теж не можна («AttributeGraph: cycle detected»), тому число
/// беруть поза розкладкою через `tracksStatusBarInset` і тримають у стані екрана.
func measuredStatusBarInset() -> CGFloat {
    UIApplication.shared.connectedScenes
        .compactMap { ($0 as? UIWindowScene)?.keyWindow?.safeAreaInsets.top }.first ?? Space.xxl
}

extension View {
    /**
     Повідомляє зміщення вмісту стрічки від її верху: 0 у спокої, більше нуля при потягу вниз,
     менше — при прокрутці. Вішається на кореневий вміст `ScrollView`, що має `.coordinateSpace(name:)`
     з тим самим ім'ям. Потрібно екранам, чий верх візуально заходить під смугу статусу: сама
     стрічка має лишатись у safe area, інакше SwiftUI не показує індикатор потягу вниз (він стає
     на верхній відступ, якого нема), тож тло під смугою малюється окремим шаром і їде за вмістом.
     */
    func reportsScrollOffset(in space: String, to offset: Binding<CGFloat>) -> some View {
        onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(space)).minY } action: { offset.wrappedValue = $0 }
    }

    /// Тримає `inset` рівним висоті смуги статусу: міряє при появі екрана і після повороту.
    func tracksStatusBarInset(_ inset: Binding<CGFloat>) -> some View {
        modifier(StatusBarInsetReader(inset: inset))
    }
}

private struct StatusBarInsetReader: ViewModifier {
    @Binding var inset: CGFloat
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    func body(content: Content) -> some View {
        content
            .onAppear { inset = measuredStatusBarInset() }
            .onChange(of: verticalSizeClass) { _, _ in inset = measuredStatusBarInset() }
    }
}

// ---- Форматування подій

let categories: [(String, String, String)] = [
    ("music", "Музика", "music.note"), ("sport", "Спорт", "figure.run"), ("art", "Мистецтво", "paintpalette"),
    ("food", "Їжа", "fork.knife"), ("games", "Ігри", "dice"), ("outdoors", "Природа", "leaf"),
    ("social", "Зустрічі", "person.2"), ("comedy", "Стендап", "mic"), ("kids", "Дітям", "balloon.2"),
    ("tours", "Екскурсії", "building.columns"), ("conference", "Конференції", "display")
]

func categoryName(_ key: String) -> String { categories.first { $0.0 == key }?.1 ?? key }
func categorySymbol(_ key: String) -> String { categories.first { $0.0 == key }?.2 ?? "mappin" }

/// Гліф категорії, двійник `categoryIcon` на Android.
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
    case "tours": PoruchIcons.tours
    case "conference": PoruchIcons.conference
    default: PoruchIcons.social
    }
}

/// Кеш форматерів за парою «пояс + шаблон»: створення `DateFormatter` дороге (ICU, локаль,
/// календар), а рядки списку перебудовуються на кожен крок скролу. Парсери незмінні й безпечні
/// між потоками (`SystemActions` розбирає дати поза головним потоком); словники під замком.
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
    formatter(zone: event.timeZone, pattern)
}

/// Той самий кеш за поясом: у сеансу прокату є пояс, але нема `Event`.
private func formatter(zone: String, _ pattern: String) -> DateFormatter {
    let key = zone + "|" + pattern
    formatterLock.lock()
    defer { formatterLock.unlock() }
    if let cached = formatters[key] { return cached }
    let formatter = DateFormatter()
    formatter.locale = ukrainian
    formatter.timeZone = TimeZone(identifier: zone)
    formatter.dateFormat = pattern
    formatters[key] = formatter
    return formatter
}

/// Календар теж кешується: `dayLabel` питає його по кілька разів на картку.
private func calendar(_ event: Event) -> Calendar { calendar(zone: event.timeZone) }

private func calendar(zone: String) -> Calendar {
    formatterLock.lock()
    defer { formatterLock.unlock() }
    if let cached = calendars[zone] { return cached }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone) ?? .current
    calendar.locale = ukrainian
    calendars[zone] = calendar
    return calendar
}

/// «Зараз» для спільної логіки: домен приймає час параметром. Не `private`, бо потрібне й `HomePresentation`.
func nowInstant() -> KotlinInstant {
    KotlinInstant.companion.fromEpochMilliseconds(
        epochMilliseconds: Int64(Date().timeIntervalSince1970 * 1000))
}

private let ukrainian = Locale(identifier: "uk_UA")

/// «У суботу о 18:00»: знахідний відмінок, щоб читалось як речення.
private let weekdayOn = ["У неділю", "У понеділок", "У вівторок", "У середу",
                         "У четвер", "У п\u{2019}ятницю", "У суботу"]

/// Дата словами людини. Поза поточним роком — з роком, інакше «13 березня» читається як минуле.
private func dayLabel(_ event: Event, _ date: Date, short: Bool) -> String {
    dayLabel(zone: event.timeZone, date, short: short)
}

private func dayLabel(zone: String, _ date: Date, short: Bool) -> String {
    let calendar = calendar(zone: zone)
    let now = Date()

    if calendar.isDateInToday(date) { return "Сьогодні" }
    if calendar.isDateInTomorrow(date) { return "Завтра" }

    let days = calendar.dateComponents([.day],
                                       from: calendar.startOfDay(for: now),
                                       to: calendar.startOfDay(for: date)).day ?? 0
    // До тижня досить назви дня, далі потрібна дата.
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
    return formatter(zone: zone, pattern).string(from: date)
}

/// Дата прокату числом: «30 вересня». Не через `dayLabel`, бо «до у суботу» — не речення.
private func plainDate(_ event: Event, _ date: Date, withYear: Bool) -> String {
    formatter(event, withYear ? "d MMMM yyyy" : "d MMMM").string(from: date)
}

/// «до 30 вересня» — підпис картки прокату. Слова ті самі, що в Android `Format.kt`.
private func untilLabel(_ event: Event) -> String? {
    guard let end = parseEventDate(event.endsAt) else { return nil }
    let calendar = calendar(event)
    let sameYear = calendar.component(.year, from: end) == calendar.component(.year, from: Date())
    return "до " + plainDate(event, end, withYear: !sameYear)
}

/// Проміжок прокату: «16 липня – 30 вересня». Рік для обох кінців разом.
private func rangeLabel(_ event: Event, _ start: Date, _ end: Date) -> String {
    let calendar = calendar(event)
    let year = calendar.component(.year, from: Date())
    let withYear = calendar.component(.year, from: start) != year || calendar.component(.year, from: end) != year
    return plainDate(event, start, withYear: withYear) + " – " + plainDate(event, end, withYear: withYear)
}

/// Надрядок картки: «СЬОГОДНІ · 18:30», «СБ, 13 БЕР. 2027 · 18:00», у поясі події. Для того,
/// що вже йде: сеанс — «ТРИВАЄ ЗАРАЗ», прокат — «ДО 30 ВЕРЕСНЯ». Слова ті самі, що в Android `Format.kt`.
func eventOverline(_ event: Event) -> String {
    guard let date = parseEventDate(event.startsAt) else { return event.startsAt }
    // Про прокат питаємо лише коли подія вже йде: невідкрита виставка показує початок, як усі.
    if event.isUnderway(now: nowInstant()) {
        if event.isMultiDay, let until = untilLabel(event) {
            return until.uppercased(with: ukrainian)
        }
        return "ТРИВАЄ ЗАРАЗ"
    }
    let hour = formatter(event, "HH:mm").string(from: date)
    return "\(dayLabel(event, date, short: true)) · \(hour)".uppercased(with: ukrainian)
}

/// Довга форма для екрана деталей. Пояс називаємо лише коли він відрізняється від поясу читача.
/// Сеанс: «Четвер, 16 липня · 18:00». Прокат: «16 липня – 30 вересня», без години.
func eventDate(_ event: Event) -> String {
    guard let date = parseEventDate(event.startsAt) else { return event.startsAt }
    let prefix = event.isUnderway(now: nowInstant()) ? "Триває зараз · " : ""
    if event.isMultiDay, let end = parseEventDate(event.endsAt) {
        return prefix + rangeLabel(event, date, end)
    }
    let hour = formatter(event, "HH:mm").string(from: date)
    let eventZone = TimeZone(identifier: event.timeZone) ?? .current
    let zoneSuffix = eventZone.secondsFromGMT(for: date) == TimeZone.current.secondsFromGMT(for: date)
        ? "" : " " + formatter(event, "z").string(from: date)
    return "\(prefix)\(dayLabel(event, date, short: false)) · \(hour)\(zoneSuffix)"
}

/// Надрядок картки: дата найближчого сеансу і, для прокату, згадка про решту. На деталях решту показує карусель.
func cardOverline(_ event: Event) -> String {
    let base = eventOverline(event)
    guard let note = seriesNote(event) else { return base }
    return base + " · " + note.uppercased(with: ukrainian)
}

/// Решта сеансів прокату: «ще 2 дати», «ще 3 сеанси», «і о 19:30». Число, а не проміжок, бо
/// прокат буває з розривами. Дні, а не сеанси, коли днів кілька. Слова ті самі, що в Android `Format.kt`.
func seriesNote(_ event: Event) -> String? {
    guard event.isSeries else { return nil }
    let days = Int(event.otherSessionDays)
    if days > 0 { return "ще \(days) \(ukrainianPlural(days, "дата", "дати", "дат"))" }
    let others = Int(event.otherSessionCount)
    if others == 1, let next = event.sessions.first(where: { $0.id != event.id }),
       let date = parseEventDate(next.startsAt) {
        return "і о " + formatter(zone: next.timeZone, "HH:mm").string(from: date)
    }
    return "ще \(others) \(ukrainianPlural(others, "сеанс", "сеанси", "сеансів"))"
}

private func ukrainianPlural(_ count: Int, _ one: String, _ few: String, _ many: String) -> String {
    if (11...14).contains(count % 100) { return many }
    switch count % 10 {
    case 1: return one
    case 2...4: return few
    default: return many
    }
}

/// Сеанс у каруселі дат: день і година окремо, бо два сеанси одного вечора інакше були б однаковими кнопками.
func sessionLabel(_ session: EventSession) -> (day: String, hour: String) {
    guard let date = parseEventDate(session.startsAt) else { return (session.startsAt, "") }
    return (dayLabel(zone: session.timeZone, date, short: true),
            formatter(zone: session.timeZone, "HH:mm").string(from: date))
}


/// Місць лишилось мало — варте бейджа. Поріг рахує домен (`Gathering.isScarce`); афіша сюди не потрапляє.
func eventScarce(_ event: Event) -> Bool {
    guard let room = event.gathering, !event.isCancelled else { return false }
    return room.isScarce
}

/// Ціна одним рядком: «безкоштовно», «від N» або «джерело не сказало». Останнє — не нуль.
func listingPrice(_ listing: Listing) -> String {
    if listing.isFree?.boolValue == true { return "Безкоштовно" }
    guard let price = listing.priceMin?.doubleValue else { return "Ціну вкаже джерело" }
    let amount = price == price.rounded() ? String(Int(price)) : String(format: "%.2f", price)
    return "Від \(amount) ₴"
}
