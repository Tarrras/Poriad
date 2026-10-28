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

/// Оболонка «Корінця» — одна нейтральна шкала з холодним відтінком: денне полотно й білі квитки, нічне графітове
/// полотно й трохи світліші квитки з волосиною по краю. Колір на екрані мають лише корінці квитків і стани.
/// Головна дія — чорнило вдень, папір уночі.
enum Palette {
    static let brand = Color(light: 0x141417, dark: 0xF3F3F0)
    static let brandPressed = Color(light: 0x2E2E33, dark: 0xD6D6D2)
    static let brandContainer = Color(light: 0xE6E6EA, dark: 0x2A2930)
    static let onBrandContainer = Color(light: 0x141417, dark: 0xF3F3F0)
    static let onBrand = Color(light: 0xFFFFFF, dark: 0x141417)

    /// Штампова фарба: терміновість, лічильник, «залишилось мало місць».
    static let accent = Color(light: 0xE0582F, dark: 0xFF8A5B)
    /// `accent` як колір дрібного тексту на білому: сам `accent` там дає 3,75:1, цей — 5,1:1. Заливкам і крапкам лишається `accent`.
    static let accentText = Color(light: 0xC2431F, dark: 0xFF8A5B)
    static let accentContainer = Color(light: 0xFDE7DF, dark: 0x3F2419)
    static let onAccentContainer = Color(light: 0x7A2E14, dark: 0xFFD9C8)

    static let success = Color(light: 0x2E7D4F, dark: 0x5DC389)
    static let successContainer = Color(light: 0xDFF3E6, dark: 0x16311F)
    static let onSuccessContainer = Color(light: 0x1B4C2F, dark: 0xBFEBD0)

    static let danger = Color(light: 0xC0392B, dark: 0xFF6B5B)
    static let dangerContainer = Color(light: 0xFBE3E0, dark: 0x3C1A16)

    static let ink = Color(light: 0x141417, dark: 0xF3F3F0)
    static let inkSecondary = Color(light: 0x5E5E66, dark: 0xA6A5AD)
    /// Контраст ≥ 4.5:1 на полотні, картці й `surfaceMuted` в обох темах: цим кольором пишуть підписи, не лише гліфи.
    static let inkTertiary = Color(light: 0x6A6A73, dark: 0x96959E)

    static let surface = Color(light: 0xFFFFFF, dark: 0x1C1B21)
    /// Те, що плаває над темним полотном, світліше за квиток у потоці.
    static let surfaceRaised = Color(light: 0xFFFFFF, dark: 0x26252C)
    static let surfaceMuted = Color(light: 0xEDEDF0, dark: 0x2A2930)
    static let canvas = Color(light: 0xF2F2F4, dark: 0x0F0F13)
    static let canvasTint = Color(light: 0xE8E8EC, dark: 0x16161B)

    static let heroTop = canvas
    static let heroBottom = canvas

    /// Тінь є лише в того, що плаває (таббар, карусель): мʼяка, нейтральна, майже непомітна.
    static let shadowSpot = Color(light: 0x000000, dark: 0x000000, lightAlpha: 0.10, darkAlpha: 0.40)
    static let shadowAmbient = Color(light: 0x000000, dark: 0x000000, lightAlpha: 0.06, darkAlpha: 0.30)

    /// Корінець скасованої події — погашений, сірий в обох темах: білий друк на ньому тримає ≥ 5:1, а сама подія
    /// не блідне прозорістю (та опускала текст нижче 3:1).
    static let voidStub = Color(light: 0x5E5E66, dark: 0x4A4950)

    /// Розділювачі у світлій темі; у темній — ще й край квитка.
    static let hairline = Color(light: 0xE0E0E5, dark: 0x2E2D35)
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
    "conference": 0x933FA8,
    // Кіно — у проміжку між пурпуром конференцій і малиною мистецтва (288°–340°), контраст 6,2:1.
    "cinema": 0xA6308A
]
private let categoryWashes: [String: UInt32] = [
    "music": 0xEBE4FB, "sport": 0xDDF0EC, "art": 0xFBE1EA, "food": 0xFBEBD9,
    "games": 0xE1EAFB, "outdoors": 0xE4F1E2, "social": 0xFAE5DA, "comedy": 0xF7ECD2, "kids": 0xD9EFEF,
    "tours": 0xECF0E4, "conference": 0xF2E8F5, "cinema": 0xF6E5F1
]

/// Палітри нижче — за `EventCategory.key`: Swift не бачить enum Kotlin вичерпним, тож таблиця читабельніша за `switch`.
/// Невідома категорія (`unknown`, ключ порожній) бере нейтральний вигляд.
func categoryColor(_ category: EventCategory) -> Color {
    guard let hue = categoryHues[category.key] else { return Palette.inkSecondary }
    return Color(light: hue, dark: hue)
}

func categoryUIColor(_ category: EventCategory) -> UIColor { UIColor(rgb: categoryHues[category.key] ?? 0x6B675E) }

/// Токени палітри для стилю мапи. MapLibre хоче hex, тому кожен резолвиться під поточну тему.
/// Резолвимо засобами SwiftUI: `UIColor(Color).resolvedColor(with:)` з голою trait collection
/// на iOS 18 віддає світлий варіант, і темна мапа виходила зі світлою землею й темною водою.
func mapTokens(_ scheme: ColorScheme) -> MapTokens {
    var environment = EnvironmentValues()
    environment.colorScheme = scheme
    func hex(_ color: Color) -> String {
        let resolved = color.resolve(in: environment)
        return String(
            format: "#%02X%02X%02X",
            Int((resolved.red * 255).rounded()), Int((resolved.green * 255).rounded()), Int((resolved.blue * 255).rounded())
        )
    }
    return MapTokens(
        canvas: hex(Palette.canvas), canvasTint: hex(Palette.canvasTint), surface: hex(Palette.surface),
        surfaceMuted: hex(Palette.surfaceMuted), hairline: hex(Palette.hairline), ink: hex(Palette.ink),
        inkSecondary: hex(Palette.inkSecondary), inkTertiary: hex(Palette.inkTertiary), dark: scheme == .dark
    )
}

/// Токен палітри знімком під тему — для растрів і шарів мапи, які кольору потім не перечитують. З `UIColor(Color)`
/// растр брав денний варіант і вночі: кластер був чорним квитком з білим краєм замість паперового, піни — білими.
func resolvedUIColor(_ color: Color, _ scheme: ColorScheme) -> UIColor {
    var environment = EnvironmentValues()
    environment.colorScheme = scheme
    let resolved = color.resolve(in: environment)
    return UIColor(red: CGFloat(resolved.red), green: CGFloat(resolved.green), blue: CGFloat(resolved.blue), alpha: CGFloat(resolved.opacity))
}

/// Заливка корінця квитка: відтінок категорії на 12 % ближче до чорного в обох темах. Сам відтінок у їжі, стендапу
/// й дитячого дає білому дрібному тексту лише 3,7–4,2:1, а день під часом набраний 12 pt.
func categoryStub(_ category: EventCategory) -> Color {
    Color(blend(categoryHues[category.key] ?? 0x6B675E, 0x000000, 0.12))
}

/// Відтінок категорії для тексту й гліфів. Удень — на 16 % темніший за сирий: той давав їжі, стендапу й дитячому на білому
/// лише 3,8–4,2:1, а з 16 % найслабша (їжа) тримає 4,55:1 навіть на полотні. Уночі освітлюється до 4.5:1.
/// `categoryColor` лишається сирим відтінком для пінів і заливок.
func categoryInk(_ category: EventCategory) -> Color {
    guard let hue = categoryHues[category.key] else { return Palette.inkSecondary }
    return Color(UIColor { $0.userInterfaceStyle == .dark ? blend(hue, 0xFFFFFF, 0.45) : blend(hue, 0x000000, 0.16) })
}

/// Корінець квитка: колір жанру, а в скасованої події — погашений сірий.
func ticketStub(_ event: Event) -> Color { event.isCalledOff ? Palette.voidStub : categoryStub(event.category) }

/// Другий відтінок пари для градієнта обкладинки.
private let categoryPartners: [String: UInt32] = [
    "music": 0xC43B6B, "sport": 0x2F63C4, "art": 0x6D4AC9, "food": 0xC43B6B,
    "games": 0x0F7F73, "outdoors": 0x0F7F73, "social": 0xC96A1E, "comedy": 0xC43B6B, "kids": 0x2F63C4,
    "tours": 0x3E7D3A, "conference": 0x6D4AC9, "cinema": 0x2F63C4
]

/// Заливка обкладинки: пастель у світлій темі, тонка вуаль у темній. Два відтінки, щоб стіна обкладинок не зливалась.
func categoryGradient(_ category: EventCategory) -> LinearGradient {
    let hue = categoryHues[category.key] ?? 0x6B675E
    let partner = categoryPartners[category.key] ?? hue
    let wash = categoryWashes[category.key] ?? 0xEDEBE4
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

/// Заливка великої картки без фото: глибокий відтінок категорії веде до сусіднього, текст поверх білий.
func categoryHeroGradient(_ category: EventCategory) -> LinearGradient {
    let hue = categoryHues[category.key] ?? 0x6B675E
    let partner = categoryPartners[category.key] ?? hue
    return LinearGradient(
        colors: [Color(UIColor(rgb: hue)), Color(UIColor(rgb: partner))], startPoint: .topLeading, endPoint: .bottomTrailing
    )
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
func categoryWash(_ category: EventCategory) -> Color {
    guard let wash = categoryWashes[category.key], let hue = categoryHues[category.key] else { return Palette.surfaceMuted }
    return Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: hue).withAlphaComponent(0.22) : UIColor(rgb: wash) })
}

/// Інтерфейс — SF Pro: ієрархію несуть кегль і вага, а не зміна регістру. Заголовки й назви подій — Sofia Sans Condensed
/// (`brandDisplay` і його брати нижче). Кожен токен — текстовий стиль системи з вагою: кегль росте з Dynamic Type.
/// Базові розміри в дужках (стандартний розмір тексту); `label` на пункт більший за колишні 14.
///
/// Sans-токени `title1`–`title3`, `cardName` лишились для цифр, значень і службових рядків (лічильники, «Сьогодні · 19:00»,
/// підписи опцій), а не для заголовків і назв: ті — голосом квитка.
enum PoruchFont {
    static let title1 = Font.system(.title, weight: .bold)             // 28
    static let title2 = Font.system(.title2, weight: .bold)            // 22
    static let title3 = Font.system(.headline, weight: .semibold)      // 17
    /// Назва картки звичайним регістром.
    static let cardName = Font.system(.headline, weight: .semibold)    // 17
    static let bodyText = Font.system(.callout)                        // 16
    static let subhead = Font.system(.subheadline)                     // 15
    static let caption = Font.system(.footnote)                        // 13
    static let label = Font.system(.subheadline, weight: .medium)      // 15
    static let button = Font.system(.callout, weight: .semibold)       // 16
    static let overline = Font.system(.caption2, weight: .semibold)    // 11
    /// Категорія під назвою: той самий гротеск, кольором категорії.
    static let descriptor = Font.system(.footnote, weight: .medium)    // 13
    /// Лід на екрані деталей.
    static let lead = Font.system(.body)                               // 17
}

/// Голос квитка — Sofia Sans Condensed (SIL OFL, статичні накреслення в `Fonts/`): назви подій і заголовки екранів та
/// секцій. Цифри корінця — Sofia Sans Extra Condensed, табличні. Правило за змістом: назва події (`Event.displayTitle`),
/// заголовок, час на корінці й штамп — так; місце, чипи, кнопки, підписи й службові рядки — системний шрифт.
/// Вужчий шрифт тримає довгі українські назви в двох рядках, тому кегль на щабель більший, ніж був у засічок.
/// `relativeTo` тримає Dynamic Type.
extension PoruchFont {
    private static func condensed(_ size: CGFloat, _ style: Font.TextStyle, heavy: Bool = false) -> Font {
        .custom(heavy ? "SofiaSansCondensed-ExtraBold" : "SofiaSansCondensed-Bold", size: size, relativeTo: style)
    }
    /// «Що поруч».
    static let brandDisplay = condensed(38, .largeTitle, heavy: true)
    /// Назва великого квитка.
    static let brandTitle1 = condensed(30, .title)
    /// Заголовок секції й назва плану.
    static let brandTitle2 = condensed(24, .title2)
    /// Назва події в квитку, постері й рядку.
    static let brandTitle3 = condensed(20, .headline)
    /// Час на корінці: «19:30». Табличні цифри дає `.monospacedDigit()` на місці виклику.
    static let numeral = Font.custom("SofiaSansExtraCondensed-ExtraBold", size: 34, relativeTo: .title)
    /// Час на малому корінці рядка.
    static let numeralSmall = Font.custom("SofiaSansExtraCondensed-ExtraBold", size: 24, relativeTo: .title3)
    /// Штамп стану: «ВИ ЙДЕТЕ», «СКАСОВАНО».
    static let stamp = condensed(13, .caption, heavy: true)
}

/// Трекінг за розміром: великий текст стискається в одну форму.
extension View {
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

/// Кути квитка: скруглені, але зібрані — предмет із картону, а не мʼяка подушка.
enum Corner {
    static let xs: CGFloat = 10
    static let sm: CGFloat = 12
    static let md: CGFloat = 14
    static let lg: CGFloat = 18
    static let xl: CGFloat = 22
    /// Пігулка: чип, бейдж, плаваюча кнопка над мапою. `RoundedRectangle` сам обрізає радіус до половини висоти, тож
    /// пігулка лишається пігулкою й тоді, коли росте з текстом.
    static let pill: CGFloat = 999
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

// ---- Рух

/// Один швидкий крок і одна пружина на весь застосунок (DS: ≤220 мс, easeInOut). Екрани беруть токен,
/// а не власну тривалість; «зменшити рух» знімає рух через `withMotion` і `.motion(value:)`.
enum Motion {
    static let quick: Animation = .easeInOut(duration: 0.2)
    static let spring: Animation = .spring(response: 0.32, dampingFraction: 0.86)
}

/// `withAnimation`, що поважає системне «зменшити рух».
func withMotion<R>(_ animation: Animation = Motion.quick, _ body: () throws -> R) rethrows -> R {
    try withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : animation, body)
}

private struct MotionModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V
    func body(content: Content) -> some View { content.animation(reduceMotion ? nil : animation, value: value) }
}

extension View {
    /// `.animation(value:)`, що поважає системне «зменшити рух».
    func motion<V: Equatable>(_ animation: Animation = Motion.quick, value: V) -> some View {
        modifier(MotionModifier(animation: animation, value: value))
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
    /// Ціль дотику щонайменше 44 pt навколо меншого кола чи слова: вигляд той самий, а палець влучає (HIG).
    /// Ставити всередині мітки кнопки: поле поза кнопкою SwiftUI до дотику не зараховує.
    func tapTarget(_ side: CGFloat = 44) -> some View {
        frame(minWidth: side, minHeight: side).contentShape(Rectangle())
    }

    /// Смуга полотна на 94 % під статус-баром: прокручений вміст кореня вкладки не лягає під годинник і Dynamic Island.
    func statusBarBand() -> some View {
        safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: 0).background(Palette.canvas.opacity(0.94)) }
    }

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

/// Те, що людина може обрати, з підписом. Порядок — як у домені; гліф дає `categoryGlyph`.
/// Назви — з `Copy`, як `categoryLabel` на Android: інакше платформи розходились («Природа» / «На природі»).
let categories: [(EventCategory, String)] = [
    (.music, Copy.music), (.sport, Copy.sport), (.art, Copy.art), (.food, Copy.food), (.games, Copy.games), (.outdoors, Copy.outdoors),
    (.social, Copy.social), (.comedy, Copy.comedy), (.kids, Copy.kids), (.tours, Copy.tours), (.conference, Copy.conference),
    (.cinema, Copy.cinema)
]

func categoryName(_ category: EventCategory) -> String { categories.first { $0.0 == category }?.1 ?? Copy.category_other }

/// Гліф категорії, двійник `categoryIcon` на Android.
func categoryGlyph(_ category: EventCategory) -> PoruchGlyph {
    switch category.key {
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
    case "cinema": PoruchIcons.cinema
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
func formatter(zone: String, _ pattern: String) -> DateFormatter {
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

func calendar(zone: String) -> Calendar {
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
/// що вже йде: сеанс — «ТРИВАЄ ЗАРАЗ», прокат — «ДО 30 ВЕРЕСНЯ». Минуле — просто датою: «20 ВЕРЕСНЯ · 14:00»,
/// бо «НД» тижневої давності читається як найближча неділя. Слова ті самі, що в Android `Format.kt`.
func eventOverline(_ event: Event) -> String {
    guard let date = parseEventDate(event.startsAt) else { return event.startsAt }
    if event.hasEnded(now: nowInstant()) {
        let calendar = calendar(event)
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: Date())
        let hour = formatter(event, "HH:mm").string(from: date)
        return "\(plainDate(event, date, withYear: !sameYear)) · \(hour)".uppercased(with: ukrainian)
    }
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

/// Що друкується на корінці квитка: велике й мале. Сеанс — година й день («19:30», «СЬОГОДНІ»); те, що вже йде, —
/// кінець прокату («30.11», «ДО») чи «ЗАРАЗ»; минуле — година й дата числом. `compact` — малий корінець рядка, де
/// «СЬОГОДНІ» не влазить: там дата завжди числом («16.10»). `medium` — нижній корінець постера: день словом лише на
/// найближчий тиждень, далі коротко «ЧТ 12.11» — «ЧТ, 12 ЛИСТ.» поруч із годиною й жанром не влазить. Слова ті самі, що
/// в Android `Format.kt`.
func stubParts(_ event: Event, compact: Bool = false, medium: Bool = false) -> (big: String, small: String) {
    guard let date = parseEventDate(event.startsAt) else { return ("—", "") }
    let now = nowInstant()
    if event.hasEnded(now: now) {
        return (formatter(event, "HH:mm").string(from: date), formatter(event, "dd.MM").string(from: date))
    }
    if event.isUnderway(now: now) {
        if event.isMultiDay, let end = parseEventDate(event.endsAt) {
            return (formatter(event, "dd.MM").string(from: end), "ДО")
        }
        return ("ЗАРАЗ", "ТРИВАЄ")
    }
    let calendar = calendar(event)
    let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: date)).day ?? 0
    let day = compact ? formatter(event, "dd.MM").string(from: date)
        : medium && !(0...6).contains(days) ? formatter(event, "EEE dd.MM").string(from: date).uppercased(with: ukrainian)
        : dayLabel(event, date, short: true).uppercased(with: ukrainian)
    return (formatter(event, "HH:mm").string(from: date), day)
}

/// Корінець зустрічі, якої ще нема (редактор): година й день, як у нижньому корінці `stubParts(medium:)`.
func draftStubParts(at date: Date, zone: String) -> (big: String, small: String) {
    let calendar = calendar(zone: zone)
    let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: date)).day ?? 0
    let day = (0...6).contains(days) ? dayLabel(zone: zone, date, short: true) : formatter(zone: zone, "EEE dd.MM").string(from: date)
    return (formatter(zone: zone, "HH:mm").string(from: date), day.uppercased(with: ukrainian))
}

/// Поле дати в редакторі: «Нд, 25 жовт.» і «19:00» у поясі події, як на Android.
func fieldDateParts(_ date: Date, zone: String) -> (day: String, time: String) {
    let day = formatter(zone: zone, "EEE, d MMM").string(from: date)
    return (day.prefix(1).uppercased() + day.dropFirst(), formatter(zone: zone, "HH:mm").string(from: date))
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

/// Стара й нова дата перенесеної афіші: «~~пт 21.11, 19:00~~ → нд 23.11, 18:00», у поясі події. Нова — та, що на корінці.
func movedLine(_ event: Event) -> Text? {
    guard let listing = event.listing, listing.isMoved, let raw = listing.previousStartsAt,
          let old = parseEventDate(raw), let new = parseEventDate(event.startsAt) else { return nil }
    let format = formatter(event, "EEE dd.MM, HH:mm")
    return Text(format.string(from: old)).strikethrough() + Text(" → " + format.string(from: new))
}

/// Час збору для питання R7а: «21:30», коли день той самий, що [ref], інакше «пт, 7 листопада о 21:30». Пояс — події.
func meetWhen(_ raw: String, ref: String?, zone: String) -> String {
    guard let at = parseEventDate(raw) else { return raw }
    if let ref, sameDay(raw, ref, zone: zone) { return formatter(zone: zone, "HH:mm").string(from: at) }
    return formatter(zone: zone, "EEE, d MMMM 'о' HH:mm").string(from: at)
}

/// Той самий календарний день у поясі [zone].
func sameDay(_ a: String, _ b: String, zone: String) -> Bool {
    guard let x = parseEventDate(a), let y = parseEventDate(b) else { return false }
    let day = formatter(zone: zone, "yyyy-MM-dd")
    return day.string(from: x) == day.string(from: y)
}

/// Стара дата перенесеної афіші довгою формою для банера деталей: «пт, 21 листопада, 19:00».
func previousDate(_ event: Event) -> String? {
    guard let raw = event.listing?.previousStartsAt, let old = parseEventDate(raw) else { return nil }
    return formatter(event, "EEE, d MMMM, HH:mm").string(from: old)
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

func ukrainianPlural(_ count: Int, _ one: String, _ few: String, _ many: String) -> String {
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
func listingPrice(_ listing: Listing) -> String { priceLabel(isFree: listing.isFree, price: listing.priceMin) }

/// Ціна одного продавця: «від 400 ₴» у рядку «Квитки».
func offerPrice(_ offer: Offer) -> String { priceLabel(isFree: offer.isFree, price: offer.priceMin) }

private func priceLabel(isFree: KotlinBoolean?, price priceMin: KotlinDouble?) -> String {
    if isFree?.boolValue == true { return "Безкоштовно" }
    guard let price = priceMin?.doubleValue else { return "Ціну вкаже джерело" }
    let amount = price == price.rounded() ? String(Int(price)) : String(format: "%.2f", price)
    return "Від \(amount) ₴"
}
