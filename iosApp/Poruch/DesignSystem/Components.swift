import SwiftUI
import Shared

// ---------------------------------------------------------------- search & chips

struct SearchField: View {
    @Binding var text: String
    var placeholder: String
    var activeFilters: Int = 0
    var onFilters: (() -> Void)?
    var body: some View {
        HStack(spacing: Space.sm) {
            HStack(spacing: Space.md) {
                PoruchIcon(glyph: PoruchIcons.search, size: 18).foregroundStyle(Palette.inkSecondary)
                TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Palette.inkTertiary))
                    .font(PoruchFont.bodyText).foregroundStyle(Palette.ink).tint(Palette.ink)
                    .submitLabel(.search).accessibilityLabel("Пошук подій")
                if !text.isEmpty {
                    Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.inkTertiary) }
                        .accessibilityLabel("Очистити пошук")
                }
            }
            .padding(.horizontal, Space.lg).frame(height: 48)
            .background(Palette.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.hairline.opacity(0.55), lineWidth: 1))
            .lifted(Elevation.card)
            if let onFilters {
                IconPill(symbol: "slider.horizontal.3", label: "Фільтри", action: onFilters)
                    .overlay(alignment: .topTrailing) {
                        if activeFilters > 0 {
                            Text("\(activeFilters)").font(PoruchFont.overline).foregroundStyle(Palette.onBrand)
                                .frame(width: 18, height: 18).background(Palette.accent, in: Circle()).offset(x: 2, y: -2)
                        }
                    }
            }
        }
    }
}

/**
 Поле пошуку, яке саме тримає набране.

 Доки текст жив у стані екрана, кожна літера перемальовувала екран цілком: списки, картки,
 підрахунки, а на мапі — ще й саму мапу. Тому набір і відставав: між натиском і буквою стояла
 вся сторінка.

 Тепер літера міняє лише саме поле. Нагору йде вже те, що набрали, — і лише коли набір
 зупинився, бо саме там починається спільний стан, тобто справжня робота.
 */
struct SearchBar: View {
    let placeholder: String
    /// Що вже шукали. Читається один раз: далі поле веде себе саме.
    let initial: String
    var activeFilters: Int = 0
    var onFilters: (() -> Void)?
    let onSettled: (String) -> Void

    @State private var text: String

    init(
        placeholder: String,
        initial: String,
        activeFilters: Int = 0,
        onFilters: (() -> Void)? = nil,
        onSettled: @escaping (String) -> Void
    ) {
        self.placeholder = placeholder
        self.initial = initial
        self.activeFilters = activeFilters
        self.onFilters = onFilters
        self.onSettled = onSettled
        _text = State(initialValue: initial)
    }

    var body: some View {
        SearchField(text: $text, placeholder: placeholder, activeFilters: activeFilters, onFilters: onFilters)
            .onSettled(text, after: .milliseconds(searchSettle), perform: onSettled)
    }
}

/// Скільки чекаємо тиші в полі. Далі йде спільний стан і мережа, тож поспіх тут нікому не потрібен.
private let searchSettle = 250

struct IconPill: View {
    let symbol: String
    let label: String
    var selected: Bool = false
    var size: CGFloat = 48
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 17, weight: .medium))
                .foregroundStyle(selected ? Palette.onBrand : Palette.ink)
                .frame(width: size, height: size)
                .background {
                    if selected { Circle().fill(brandGradient) } else { Circle().fill(Palette.surface) }
                }
                .overlay(Circle().strokeBorder(Palette.hairline, lineWidth: selected ? 0 : 1))
                .lifted(Elevation.card)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }
}

/// The smallest possible carrier of category colour, straight from Corner.
struct CategoryDot: View {
    let category: String
    var size: CGFloat = 8
    var body: some View { Circle().fill(categoryInk(category)).frame(width: size, height: size) }
}

/**
 Chip: lowercase label on a white pill that hovers a millimetre off the paper; selection fills it
 with ink, the way Corner marks state. A selected chip sits *higher* than an unselected one — the
 state is legible from the shadow alone, before the fill is read.
 */
struct Chip: View {
    let label: String
    var symbol: String?
    var dot: String?
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.sm) {
                if let dot {
                    Circle().fill(selected ? Palette.onBrand : categoryInk(dot)).frame(width: 8, height: 8)
                } else if let symbol {
                    Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selected ? Palette.onBrand : Palette.inkSecondary)
                }
                Text(label).font(PoruchFont.label)
            }
            .foregroundStyle(selected ? Palette.onBrand : Palette.ink)
            .padding(.horizontal, Space.lg).frame(height: 38)
            .background {
                if selected { Capsule().fill(brandGradient) } else { Capsule().fill(Palette.surface) }
            }
            .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: selected ? 0 : 1))
            .lifted(selected ? Elevation.raised : Elevation.card)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A rounded square washed in the category pastel, as Corner sets its rating tiles.
struct CategoryTile: View {
    let category: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: Space.sm) {
                PoruchIcon(glyph: categoryGlyph(category), size: 24)
                    .foregroundStyle(categoryInk(category))
                    .frame(width: 60, height: 60)
                    .background(
                        categoryGradient(category),
                        in: RoundedRectangle(cornerRadius: Corner.sm, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Corner.sm, style: .continuous)
                            .strokeBorder(
                                selected ? Palette.ink : categoryColor(category).opacity(0.18),
                                lineWidth: selected ? 2 : 1
                            )
                    )
                    // The tile glows in its own hue rather than smudging the page with grey.
                    .lifted(Elevation.card, tint: categoryColor(category).opacity(0.28))
                Text(categoryName(category)).font(PoruchFont.label).lineLimit(1)
                    .foregroundStyle(selected ? Palette.ink : Palette.inkSecondary)
            }.frame(width: 76)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(categoryName(category))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// ---------------------------------------------------------------- badges & buttons

enum BadgeTone { case brand, success, accent, danger, neutral }

struct StatusBadge: View {
    let text: String
    var tone: BadgeTone = .neutral
    var symbol: String?
    private var colors: (Color, Color) {
        switch tone {
        case .brand: return (Palette.brandContainer, Palette.onBrandContainer)
        case .success: return (Palette.successContainer, Palette.onSuccessContainer)
        case .accent: return (Palette.accentContainer, Palette.onAccentContainer)
        case .danger: return (Palette.dangerContainer, Palette.danger)
        case .neutral: return (Palette.surfaceMuted, Palette.inkSecondary)
        }
    }
    var body: some View {
        HStack(spacing: Space.xs) {
            if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .bold)) }
            Text(text.uppercased()).font(PoruchFont.overline).kerning(1.2)
        }
        .foregroundStyle(colors.1)
        .padding(.horizontal, Space.md).padding(.vertical, 5)
        .background(toneGradient(colors.0, colors.1), in: Capsule())
    }
}

struct PrimaryButton: View {
    let title: String
    var symbol: String?
    var tone: Color?
    var loading: Bool = false
    var enabled: Bool = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.sm) {
                if loading { ProgressView().tint(Palette.onBrand) }
                else if let symbol { Image(systemName: symbol).font(.system(size: 15, weight: .semibold)) }
                Text(title).font(PoruchFont.button).lineLimit(1)
            }
            .foregroundStyle(enabled ? Palette.onBrand : Palette.inkTertiary)
            .padding(.horizontal, Space.xxl).frame(height: 52).frame(maxWidth: .infinity)
            .background {
                switch (enabled, tone) {
                case (false, _): Capsule().fill(Palette.surfaceMuted)
                case (true, .some(let tone)): Capsule().fill(LinearGradient(colors: [tone.opacity(0.92), tone], startPoint: .top, endPoint: .bottom))
                case (true, .none): Capsule().fill(brandGradient)
                }
            }
            // The action's own shadow is tinted with the action's own colour, so a coloured button
            // glows rather than casting the same grey smudge as everything else.
            .lifted(enabled ? Elevation.raised : 0, tint: enabled ? (tone ?? Palette.ink).opacity(0.28) : nil)
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled || loading)
    }
}

struct SecondaryButton: View {
    let title: String
    var symbol: String?
    var tone: Color?
    var enabled: Bool = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.sm) {
                if let symbol { Image(systemName: symbol).font(.system(size: 15, weight: .semibold)) }
                Text(title).font(PoruchFont.button).lineLimit(1)
            }
            .foregroundStyle(enabled ? tone ?? Palette.ink : Palette.inkTertiary)
            .padding(.horizontal, Space.xxl).frame(height: 52).frame(maxWidth: .infinity)
            .background(Palette.surfaceMuted, in: Capsule())
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
    }
}

// ---------------------------------------------------------------- structure

/**
 A section is announced the way Corner announces one: lowercase, at reading size, in the ink of the
 content it introduces. The 11 pt caps we used before were legible but timid — they read as a
 caption for the card above rather than a title for the row below. Caps stay where they carry data:
 dates, badges, field labels.
 */
struct SectionHeader: View {
    let title: String
    var actionLabel: String?
    var action: (() -> Void)?
    var body: some View {
        HStack {
            Text(title.lowercased()).font(PoruchFont.sectionTitle).kerning(-0.3).foregroundStyle(Palette.ink)
            Spacer(minLength: Space.sm)
            if let actionLabel, let action {
                Button(actionLabel, action: action).font(PoruchFont.label).foregroundStyle(Palette.ink)
            }
        }
    }
}

struct PageHeader<Trailing: View>: View {
    let title: String
    var back: (() -> Void)?
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(spacing: Space.md) {
            if let back {
                Button(action: back) {
                    Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.ink)
                        .frame(width: 40, height: 40).background(Palette.surface, in: Circle())
                        .overlay(Circle().strokeBorder(Palette.hairline.opacity(0.55), lineWidth: 1))
                        .lifted(Elevation.card)
                }.buttonStyle(PressableStyle()).accessibilityLabel("Назад")
            }
            Text(title).font(PoruchFont.title1).titleTracking().foregroundStyle(Palette.ink)
            Spacer(minLength: 0)
            trailing
        }.padding(.horizontal, Space.page).padding(.vertical, Space.md)
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, back: (() -> Void)? = nil) { self.init(title: title, back: back) { EmptyView() } }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var compact: Bool = false
    var actionLabel: String?
    var action: (() -> Void)?
    var body: some View {
        VStack(spacing: compact ? Space.sm : Space.md) {
            Image(systemName: symbol).font(.system(size: compact ? 20 : 26, weight: .medium)).foregroundStyle(Palette.inkSecondary)
                .frame(width: compact ? 52 : 64, height: compact ? 52 : 64)
                .background(
                    LinearGradient(colors: [Palette.surface, Palette.surfaceMuted], startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: Corner.md, style: .continuous)
                )
                .overlay(RoundedRectangle(cornerRadius: Corner.md, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
                .lifted(Elevation.card)
            Text(title).font(compact ? PoruchFont.title3 : PoruchFont.title2).foregroundStyle(Palette.ink).multilineTextAlignment(.center)
            Text(message).font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary).multilineTextAlignment(.center)
            if let actionLabel, let action {
                PrimaryButton(title: actionLabel, action: action).fixedSize(horizontal: true, vertical: false).padding(.top, Space.sm)
            }
        }.padding(compact ? Space.md : Space.xxl).frame(maxWidth: .infinity)
    }
}

struct BannerCard: View {
    let title: String
    let subtitle: String
    var symbol: String = "sparkles"
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.md) {
                Image(systemName: symbol).font(.system(size: 17, weight: .medium)).foregroundStyle(Palette.ink)
                    .frame(width: 44, height: 44)
                    .background(
                        LinearGradient(colors: [Palette.surface, Palette.brandContainer], startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: Corner.xs, style: .continuous)
                    )
                    .overlay(RoundedRectangle(cornerRadius: Corner.xs, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(PoruchFont.cardName).foregroundStyle(Palette.ink).multilineTextAlignment(.leading)
                    Text(subtitle).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.onBrand)
                    .frame(width: 32, height: 32).background(Palette.brand, in: Circle())
            }
            .padding(Space.lg)
            // The one warm-lit surface on the home screen: it invites rather than informs.
            .background(
                LinearGradient(colors: [Palette.heroTop, Palette.surface], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: Corner.lg, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: Corner.lg, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
            .lifted(Elevation.card)
        }.buttonStyle(PressableStyle())
    }
}

/// Overlapping avatars, the social proof Meetup puts under every event.
struct AvatarStack: View {
    let attendees: [Attendee]
    var total: Int
    var size: CGFloat = 32
    private var shown: [Attendee] { Array(attendees.prefix(5)) }
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.userId) { index, attendee in
                ZStack {
                    Circle().fill(Palette.surfaceMuted)
                    Text(attendee.name.trimmingCharacters(in: .whitespaces).prefix(1).uppercased())
                        .font(PoruchFont.label).foregroundStyle(Palette.inkSecondary)
                    if let source = attendee.avatarUrl, let url = URL(string: source), url.scheme == "https" {
                        // Той самий кеш, що й у картках: `AsyncImage` не пам'ятає нічого й читає
                        // аватар наново щоразу, коли рядок повертається на екран.
                        CachedImage(url: url, maxDimension: size).clipShape(Circle())
                    }
                }
                .frame(width: size, height: size)
                .overlay(Circle().strokeBorder(Palette.surface, lineWidth: 2))
                .offset(x: CGFloat(-index * 10))
                .zIndex(Double(shown.count - index))
            }
            if total > shown.count {
                Text("+\(total - shown.count)").font(PoruchFont.label).foregroundStyle(Palette.inkSecondary)
                    .offset(x: CGFloat(-shown.count * 10 + 4))
            }
        }.accessibilityElement(children: .ignore).accessibilityLabel("Учасників: \(total)")
    }
}

struct MetaLine: View {
    let symbol: String
    let text: String
    var tone: Color?
    var body: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(tone ?? Palette.inkTertiary).frame(width: 15)
            Text(text).font(PoruchFont.caption).foregroundStyle(tone ?? Palette.inkSecondary).lineLimit(1)
        }
    }
}

struct InfoRow: View {
    let symbol: String
    let label: String
    let value: String
    var body: some View {
        HStack(alignment: .top, spacing: Space.md) {
            Image(systemName: symbol).font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.inkSecondary)
                .frame(width: 34, height: 34)
                .background(
                    LinearGradient(colors: [Palette.surface, Palette.surfaceMuted], startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: Corner.xs, style: .continuous)
                )
                .overlay(RoundedRectangle(cornerRadius: Corner.xs, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased()).font(PoruchFont.overline).kerning(1.2).foregroundStyle(Palette.inkTertiary)
                Text(value).font(PoruchFont.bodyText).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }.accessibilityElement(children: .combine)
    }
}

/**
 Field in the Corner idiom: a small uppercase label above the box rather than a floating
 placeholder, so a form reads as a list of named things and every field looks the same.
 */
struct LabelledField<Trailing: View>: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var hint: String?
    var secure: Bool = false
    /// A description grows with what is typed; every other field stays one line tall.
    var multiline: Bool = false
    @ViewBuilder var trailing: Trailing
    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(label.uppercased()).font(PoruchFont.overline).kerning(1.2).foregroundStyle(Palette.inkTertiary)
            HStack(spacing: Space.sm) {
                Group {
                    if secure {
                        SecureField("", text: $text, prompt: Text(placeholder).foregroundStyle(Palette.inkTertiary))
                    } else if multiline {
                        TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Palette.inkTertiary), axis: .vertical)
                            .lineLimit(4...10)
                    } else {
                        TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Palette.inkTertiary))
                    }
                }
                .font(PoruchFont.bodyText).foregroundStyle(Palette.ink).tint(Palette.ink).textFieldStyle(.plain)
                trailing
            }
            // A trailing control reserves a 44 pt target, so the box is tall enough to hold one
            // without growing past a plain field beside it.
            .padding(.horizontal, Space.lg)
            .padding(.vertical, multiline ? Space.md : 0)
            .frame(minHeight: 56, alignment: multiline ? .top : .center)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Corner.sm, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Corner.sm, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
            if let hint {
                Text(hint).font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary)
            }
        }
    }
}

extension LabelledField where Trailing == EmptyView {
    init(
        label: String, text: Binding<String>, placeholder: String = "",
        hint: String? = nil, secure: Bool = false, multiline: Bool = false
    ) {
        self.init(label: label, text: text, placeholder: placeholder, hint: hint, secure: secure, multiline: multiline) {
            EmptyView()
        }
    }
}

// ---------------------------------------------------------------- event surfaces

/**
 A cover with no photo is not an empty box: it is the category's own gradient with the category's
 glyph on it, so a feed of photoless events still reads as a row of coloured objects. A photo, when
 there is one, gets a scrim at top and bottom — the badge and the save button sit on it, and a
 bright sky underneath would swallow both.
 */
struct EventThumbnail: View {
    let event: Event
    /// The hero on a detail screen is 300 pt tall; a 24 pt glyph on it reads as a speck.
    var glyphSize: CGFloat = 24
    /// Найбільша сторона показу в точках. За нею [CachedImage] зменшує зображення ще під час
    /// розпакування — у рядок 60×60 немає сенсу класти мільйон пікселів.
    var maxDimension: CGFloat = 200
    var body: some View {
        ZStack {
            categoryGradient(event.category)
            PoruchIcon(glyph: categoryGlyph(event.category), size: glyphSize)
                .foregroundStyle(categoryInk(event.category))
            if let source = event.imageUrl, let url = URL(string: source), url.scheme == "https" {
                CachedImage(url: url, maxDimension: maxDimension)
                    .overlay(
                        LinearGradient(
                            colors: [.black.opacity(0.28), .clear, .black.opacity(0.12)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
            }
        }.decorative()
    }
}

/// Один рядок стану над карткою.
///
/// Афіша завжди підписана джерелом, і це не стилістика: без видимої атрибуції ми не маємо права
/// її показувати (docs/event-ingestion.md §8). Місця й «ви йдете» стосуються тільки кімнати —
/// тепер до них не дістатися, не спитавши спершу, чи вона взагалі є.
func eventBadge(_ event: Event, waitlisted: Bool = false) -> (String, BadgeTone, String?)? {
    if event.isCancelled { return ("Скасовано", .danger, nil) }
    if let listing = event.listing {
        if listing.isWithdrawn { return ("Більше не проводиться", .neutral, nil) }
        return ("Афіша · \(listing.sourceName)", .neutral, nil)
    }
    guard let room = event.gathering else { return nil }
    if room.joined { return ("Ви йдете", .success, "checkmark") }
    if waitlisted { return ("У черзі", .accent, "hourglass") }
    if room.isFull { return ("Місць немає", .neutral, nil) }
    if room.isScarce { return ("Лишилось \(room.seatsLeft)", .accent, nil) }
    return nil
}

/// Рядок під назвою: скільки людей іде — або скільки коштує квиток. Що саме, вирішує наявність
/// кімнати, а не збіг обставин: «0 з 1 учасників» під чужим концертом було саме цим збігом.
struct EventMeta: View {
    let event: Event
    var short = false
    var body: some View {
        if let room = event.gathering {
            MetaLine(
                symbol: "person.2",
                text: short ? "\(room.attendeeCount) з \(room.capacity)" : "\(room.attendeeCount) з \(room.capacity) учасників"
            )
        } else if let listing = event.listing {
            MetaLine(symbol: "ticket", text: listingPrice(listing))
        }
    }
}

/// Category dot plus a lowercase descriptor — the line Corner puts under every place name.
struct EventDescriptor: View {
    let event: Event
    var body: some View {
        HStack(spacing: Space.sm) {
            CategoryDot(category: event.category)
            // The serif italic is the category; the grotesque caption is the place. One line, two
            // voices, so «what this is» never reads as part of the address.
            Text(categoryName(event.category).lowercased())
                .font(PoruchFont.descriptor).foregroundStyle(categoryInk(event.category)).lineLimit(1)
            Text((event.address.isEmpty ? event.city : event.address).isEmpty ? "" : "· " + (event.address.isEmpty ? event.city : event.address))
                .font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary).lineLimit(1)
        }
    }
}

struct SaveButton: View {
    let saved: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: saved ? "bookmark.fill" : "bookmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(saved ? Palette.ink : Palette.inkSecondary)
                .frame(width: 34, height: 34)
                .background(Palette.surface, in: Circle())
                .overlay(Circle().strokeBorder(Palette.hairline, lineWidth: 1))
                // It sits on a photo, so it carries its own shadow in both appearances.
                .shadow(color: .black.opacity(0.22), radius: 6, y: 2)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(saved ? "Прибрати зі збережених" : "Зберегти подію")
    }
}

/// Feed card: photo, then the date overline, the name and one descriptor line.
struct EventCard: View {
    let event: Event
    var saved: Bool = false
    var waitlisted: Bool = false
    var onSave: (() -> Void)?
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                // Without a photo the placeholder shrinks: an empty 16:9 band would dominate the card.
                EventThumbnail(event: event, maxDimension: 420)
                    .frame(height: event.imageUrl == nil ? 96 : 168).frame(maxWidth: .infinity).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: Corner.sm, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        if let badge = eventBadge(event, waitlisted: waitlisted) {
                            StatusBadge(text: badge.0, tone: badge.1, symbol: badge.2).padding(Space.sm)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if let onSave { SaveButton(saved: saved, action: onSave).padding(Space.sm) }
                    }
                VStack(alignment: .leading, spacing: Space.sm) {
                    Text(eventOverline(event)).font(PoruchFont.overline).kerning(1.2).foregroundStyle(Palette.inkTertiary)
                    Text(event.title.uppercased()).font(PoruchFont.cardName).kerning(0.3).foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.leading).lineLimit(2)
                    EventDescriptor(event: event)
                    EventMeta(event: event)
                }.padding(Space.md).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Space.sm)
            .cardSurface()
            .opacity(event.isCancelled ? 0.6 : 1)
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .combine)
    }
}

/// Compact row for lists: square thumbnail, name, descriptor.
struct EventRow: View {
    let event: Event
    var body: some View {
        HStack(spacing: Space.md) {
            EventThumbnail(event: event, maxDimension: 60)
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: Corner.xs, style: .continuous))
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(eventOverline(event)).font(PoruchFont.overline).kerning(1.2).foregroundStyle(Palette.inkTertiary)
                Text(event.title.uppercased()).font(PoruchFont.cardName).kerning(0.3).foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.leading).lineLimit(2)
                if let badge = eventBadge(event) { StatusBadge(text: badge.0, tone: badge.1, symbol: badge.2) }
                else { EventDescriptor(event: event) }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.inkTertiary)
        }
        .padding(.vertical, Space.md)
        .opacity(event.isCancelled ? 0.6 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Висота картки каруселі: її знає й сама карусель, коли рахує свою висоту.
let mapCardHeight: CGFloat = 112

/// Carousel card above the map: wide enough for the name, short enough to leave the map readable.
struct EventMapCard: View {
    let event: Event
    var focused: Bool = false
    var saved: Bool = false
    var onSave: (() -> Void)?
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.md) {
                EventThumbnail(event: event, maxDimension: 84)
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: Corner.xs, style: .continuous))
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(eventOverline(event)).font(PoruchFont.overline).kerning(1.2).foregroundStyle(Palette.inkTertiary)
                    Text(event.title.uppercased()).font(PoruchFont.cardName).kerning(0.3).foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.leading).lineLimit(2)
                    if let badge = eventBadge(event) { StatusBadge(text: badge.0, tone: badge.1, symbol: badge.2) }
                    else { EventMeta(event: event, short: true) }
                }
                Spacer(minLength: 0)
                if let onSave { SaveButton(saved: saved, action: onSave) }
            }
            .padding(Space.md)
            .frame(height: mapCardHeight)
            .cardSurface(radius: Corner.lg, elevation: Elevation.overlay)
            .overlay(
                RoundedRectangle(cornerRadius: Corner.lg, style: .continuous)
                    .strokeBorder(Palette.ink, lineWidth: focused ? 2 : 0)
            )
            .opacity(event.isCancelled ? 0.6 : 1)
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(focused ? .isSelected : [])
    }
}

/// Narrow tile for horizontal rails on the home screen.
struct EventTile: View {
    let event: Event
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Space.sm) {
                EventThumbnail(event: event, maxDimension: 240)
                    .frame(height: 104).frame(maxWidth: .infinity).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: Corner.xs, style: .continuous))
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(eventOverline(event)).font(PoruchFont.overline).kerning(1.2).foregroundStyle(Palette.inkTertiary)
                    Text(event.title.uppercased()).font(PoruchFont.cardName).kerning(0.3).foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.leading).lineLimit(2, reservesSpace: true)
                    EventDescriptor(event: event)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Space.sm).padding(.bottom, Space.sm)
            }
            .padding(Space.sm)
            .cardSurface()
            .opacity(event.isCancelled ? 0.6 : 1)
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .combine)
    }
}

// ---------------------------------------------------------------- navigation

struct TabItem: Identifiable {
    let id: Int
    let label: String
    let glyph: PoruchGlyph
}

/**
 Плаваюча панель вкладок живе поверх усього застосунку, а не всередині навігаційного стека, тож
 екран, який займає весь простір, мусить сказати про себе сам. Деталі події — саме такий екран: у
 них власна нижня панель із дією, і дві панелі одна на одній перекривали одна одну.

 Прапорець їде вгору як preference, бо йому треба перетнути `NavigationStack`, у який кореневий
 екран не має доступу.
 */
/**
 Перемкнути застосунок на вкладку «Мапа». Живе в оточенні, бо вкладками керує корінь, а просить
 про це екран, який лежить у навігаційному стеку й до кореня не дотягується.
 */
private struct OpenMapKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var openMap: () -> Void {
        get { self[OpenMapKey.self] }
        set { self[OpenMapKey.self] = newValue }
    }
}

struct HidesTabBarKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

extension View {
    /// Позначає екран, поверх якого плаваюча панель вкладок стояти не має.
    func hidesTabBar() -> some View { preference(key: HidesTabBarKey.self, value: true) }
}

/// Floating capsule bar; the active item is inked while the rest stay quiet, as Corner marks tabs.
struct PoruchTabBar<Trailing: View>: View {
    let items: [TabItem]
    @Binding var selection: Int
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(spacing: Space.sm) {
            HStack(spacing: 0) {
                ForEach(items) { item in
                    Button { selection = item.id } label: {
                        VStack(spacing: 3) {
                            // The active tab is inked rather than thickened: the glyphs are one
                            // weight, so swapping stroke widths would make the row jitter.
                            PoruchIcon(glyph: item.glyph, size: 22)
                            Text(item.label).font(PoruchFont.overline).lineLimit(1)
                        }
                        .foregroundStyle(selection == item.id ? Palette.ink : Palette.inkTertiary)
                        .frame(maxWidth: .infinity).frame(height: 42)
                        .background {
                            // A tonal pill under the active glyph: the state survives a glance at
                            // arm's length, where a colour difference alone does not.
                            if selection == item.id { Capsule().fill(Palette.brandContainer) }
                        }
                    }
                    .buttonStyle(PressableStyle(pressedScale: 0.94))
                    .accessibilityLabel(item.label)
                    .accessibilityAddTraits(selection == item.id ? .isSelected : [])
                }
            }
            .padding(.horizontal, Space.xs).padding(.vertical, Space.sm)
            .cardSurface(radius: 32, elevation: Elevation.overlay)
            trailing
        }.padding(.horizontal, Space.lg)
    }
}

struct CreateButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            PoruchIcon(glyph: PoruchIcons.plus, size: 24).foregroundStyle(Palette.onBrand)
                .frame(width: 56, height: 56).background(brandGradient, in: Circle())
                // Warm glow rather than a grey drop: the one always-visible action gets colour
                // without becoming a coloured button.
                .shadow(color: Palette.accent.opacity(0.45), radius: 14, y: 6)
                .shadow(color: .black.opacity(0.16), radius: 5, y: 2)
        }
        .buttonStyle(PressableStyle(pressedScale: 0.94))
        .accessibilityLabel("Створити подію")
    }
}
