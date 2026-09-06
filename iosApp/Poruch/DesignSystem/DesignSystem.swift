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
    /// Resolves per trait collection so every token follows the viewer's appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light) })
    }
}

/// Warm paper ground, white cards, near-black actions — the Corner reading of our palette.
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

    static let surface = Color(light: 0xFFFFFF, dark: 0x1C1B19)
    static let surfaceMuted = Color(light: 0xEDEBE4, dark: 0x26241F)
    static let canvas = Color(light: 0xF2F1ED, dark: 0x131211)
    static let canvasTint = Color(light: 0xEAE7DE, dark: 0x1B1A18)
    static let hairline = Color(light: 0xE3E0D7, dark: 0x2F2D29)
}

/// Every category owns a deep hue for glyphs and text, plus a pastel wash for tiles and pins.
private let categoryHues: [String: UInt32] = [
    "music": 0x6D4AC9, "sport": 0x0F7F73, "art": 0xC43B6B, "food": 0xC96A1E,
    "games": 0x2F63C4, "outdoors": 0x3E7D3A, "social": 0xB8562F
]
private let categoryWashes: [String: UInt32] = [
    "music": 0xEBE4FB, "sport": 0xDDF0EC, "art": 0xFBE1EA, "food": 0xFBEBD9,
    "games": 0xE1EAFB, "outdoors": 0xE4F1E2, "social": 0xFAE5DA
]

func categoryColor(_ category: String) -> Color {
    guard let hue = categoryHues[category] else { return Palette.inkSecondary }
    return Color(light: hue, dark: hue)
}

func categoryUIColor(_ category: String) -> UIColor { UIColor(rgb: categoryHues[category] ?? 0x6B675E) }

/// Pastel in light mode; in dark the same hue is dropped to a low-alpha veil over the surface.
func categoryWash(_ category: String) -> Color {
    guard let wash = categoryWashes[category], let hue = categoryHues[category] else { return Palette.surfaceMuted }
    return Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: hue).withAlphaComponent(0.22) : UIColor(rgb: wash) })
}

enum PoruchFont {
    static let display = Font.system(size: 30, weight: .bold)
    static let title1 = Font.system(size: 24, weight: .bold)
    static let title2 = Font.system(size: 19, weight: .bold)
    static let title3 = Font.system(size: 16, weight: .semibold)
    /// Card names are set in caps, the way Corner sets place names.
    static let cardName = Font.system(size: 15, weight: .bold)
    static let bodyText = Font.system(size: 15)
    static let subhead = Font.system(size: 14)
    static let caption = Font.system(size: 13)
    static let label = Font.system(size: 13, weight: .medium)
    static let button = Font.system(size: 15, weight: .semibold)
    static let overline = Font.system(size: 11, weight: .bold)
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
    static let lg: CGFloat = 18
    static let xl: CGFloat = 26
}

/// Card and panel elevation: a soft shadow in light mode, a hairline outline in dark mode.
struct CardSurface: ViewModifier {
    var radius: CGFloat = Corner.lg
    var elevation: CGFloat = 0
    func body(content: Content) -> some View {
        content
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1)
            )
            .shadow(color: .black.opacity(elevation > 0 ? 0.06 : 0), radius: elevation, y: elevation / 3)
    }
}

extension View {
    func cardSurface(radius: CGFloat = Corner.lg, elevation: CGFloat = 0) -> some View {
        modifier(CardSurface(radius: radius, elevation: elevation))
    }
    /// Photos carry no information the title does not, so they stay out of the accessibility tree.
    func decorative() -> some View { accessibilityHidden(true) }
}

// ---------------------------------------------------------------- event formatting

let categories: [(String, String, String)] = [
    ("music", "Музика", "music.note"), ("sport", "Спорт", "figure.run"), ("art", "Мистецтво", "paintpalette"),
    ("food", "Їжа", "fork.knife"), ("games", "Ігри", "dice"), ("outdoors", "Природа", "leaf"),
    ("social", "Зустрічі", "person.2")
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
    default: PoruchIcons.social
    }
}

func parseEventDate(_ value: String) -> Date? {
    let parser = ISO8601DateFormatter()
    if let date = parser.date(from: value) { return date }
    parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return parser.date(from: value)
}

private func formatter(_ event: Event, _ pattern: String) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "uk_UA")
    formatter.timeZone = TimeZone(identifier: event.timeZone)
    formatter.dateFormat = pattern
    return formatter
}

/// Overline above a card title: «СБ, 11 ЛИП · 18:30». Always rendered in the event's own zone.
func eventOverline(_ event: Event) -> String {
    guard let date = parseEventDate(event.startsAt) else { return event.startsAt }
    return formatter(event, "EEE, d MMM · HH:mm").string(from: date).uppercased(with: Locale(identifier: "uk_UA"))
}

/// Long form for the detail screen, with the zone abbreviation so travellers are not misled.
func eventDate(_ event: Event) -> String {
    guard let date = parseEventDate(event.startsAt) else { return event.startsAt }
    return formatter(event, "EEEE, d MMMM · HH:mm z").string(from: date)
}


/// True once the remaining capacity is small enough to be worth an urgency badge.
/// A fifth of the room left reads as "hurry"; below three seats it always does.
private let scarcityFraction = 5
private let minScarceSeats = 3

/// True once the remaining capacity is small enough to be worth an urgency badge.
func eventScarce(_ event: Event) -> Bool {
    let left = Int(event.seatsLeft)
    return !event.isCancelled && left > 0 && left <= max(minScarceSeats, Int(event.capacity) / scarcityFraction)
}
