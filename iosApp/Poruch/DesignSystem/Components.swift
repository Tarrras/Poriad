import SwiftUI
import Shared

// ---- Пошук і чипи

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

/// Поле пошуку з власним текстом: літера міняє лише поле, нагору йде результат після паузи.
/// Інакше кожна літера перемальовувала весь екран разом із мапою.
struct SearchBar: View {
    let placeholder: String
    /// Початковий текст. Читається один раз.
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

/// Пауза після набору перед оновленням спільного стану.
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

/// Крапка категорії: найменший носій її кольору.
struct CategoryDot: View {
    let category: String
    var size: CGFloat = 8
    var body: some View { Circle().fill(categoryInk(category)).frame(width: size, height: size) }
}

/// Чип: біла пігулка над папером; обраний заливається чорнилом і сидить вище, тож стан видно з тіні.
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

/// Плитка категорії: скруглений квадрат у пастелі категорії.
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
                    // Плитка світиться власним відтінком, а не сірою тінню.
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

// ---- Бейджі й кнопки

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
                if loading { ProgressView().tint(enabled ? Palette.onBrand : Palette.inkTertiary) }
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
            // Тінь кнопки тонована її кольором.
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

// ---- Структура

/// Заголовок секції малими літерами читабельного розміру. Капітель лишається там, де несе дані.
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
            // Єдина тепло підсвічена поверхня на головній: запрошує, а не інформує.
            .background(
                LinearGradient(colors: [Palette.heroTop, Palette.surface], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: Corner.lg, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: Corner.lg, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
            .lifted(Elevation.card)
        }.buttonStyle(PressableStyle())
    }
}

/// Аватари внапуск.
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
                        // Той самий кеш, що в картках: `AsyncImage` нічого не пам'ятає.
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

/// Поле з малим підписом над рамкою замість плаваючого плейсхолдера: форма читається як список названих речей.
struct LabelledField<Trailing: View>: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var hint: String?
    var secure: Bool = false
    /// Опис росте з текстом; решта полів однорядкові.
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
            // Висота вміщує 44 pt ціль кінцевого контролу, не переростаючи сусіднє поле.
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

// ---- Поверхні подій

/// Обкладинка без фото — градієнт категорії з її гліфом. Фото отримує затемнення під бейдж і кнопку збереження.
struct EventThumbnail: View {
    let event: Event
    /// На 300 pt хіро деталей гліф 24 pt виглядає як цятка.
    var glyphSize: CGFloat = 24
    /// Найбільша сторона показу в pt: `CachedImage` зменшує зображення ще при розпакуванні.
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

/// Рядок стану над карткою. Афіша завжди підписана джерелом (docs/event-ingestion.md §8); місця лише в кімнати.
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

/// Рядок під назвою: учасники для кімнати, ціна для афіші.
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

/// Крапка категорії плюс опис малими літерами.
struct EventDescriptor: View {
    let event: Event
    var body: some View {
        HStack(spacing: Space.sm) {
            CategoryDot(category: event.category)
            // Антиква — категорія, гротеск — місце: «що це» не читається як частина адреси.
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
                // На фото, тому з власною тінню в обох темах.
                .shadow(color: .black.opacity(0.22), radius: 6, y: 2)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(saved ? "Прибрати зі збережених" : "Зберегти подію")
    }
}

/// Картка стрічки: фото, надрядок дати, назва, рядок опису.
struct EventCard: View {
    let event: Event
    var saved: Bool = false
    var waitlisted: Bool = false
    var onSave: (() -> Void)?
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                // Без фото плейсхолдер нижчий: порожній 16:9 домінував би на картці.
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
                    Text(cardOverline(event)).font(PoruchFont.overline).kerning(1.2).foregroundStyle(Palette.inkTertiary)
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

/// Компактний рядок списку: квадратне превʼю, назва, опис.
struct EventRow: View {
    let event: Event
    var body: some View {
        HStack(spacing: Space.md) {
            EventThumbnail(event: event, maxDimension: 60)
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: Corner.xs, style: .continuous))
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(cardOverline(event)).font(PoruchFont.overline).kerning(1.2).foregroundStyle(Palette.inkTertiary)
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

/// Висота картки каруселі, потрібна і самій каруселі.
let mapCardHeight: CGFloat = 112

/// Картка каруселі над мапою: досить широка для назви, досить низька, щоб мапу було видно.
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
                    Text(cardOverline(event)).font(PoruchFont.overline).kerning(1.2).foregroundStyle(Palette.inkTertiary)
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

/// Вузька плитка для горизонтальних стрічок головної.
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
                    Text(cardOverline(event)).font(PoruchFont.overline).kerning(1.2).foregroundStyle(Palette.inkTertiary)
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

// ---- Навігація

struct TabItem: Identifiable {
    let id: Int
    let label: String
    let glyph: PoruchGlyph
    /// Скільки справ чекає: 0 — без бейджа.
    var badge: Int = 0
}

/// Таббар плаває поверх застосунку, тож екран із власною нижньою панеллю (деталі) має сам
/// попросити його сховати. Preference, бо треба перетнути `NavigationStack`.

/// Перемкнути на вкладку «Мапа». В оточенні, бо вкладками керує корінь, а просить екран зі стека.
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
    /// Екран, над яким таббар не показуємо.
    func hidesTabBar() -> some View { preference(key: HidesTabBarKey.self, value: true) }
}

/// Плаваючий таббар-капсула; активний пункт залитий чорнилом.
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
                            // Активна вкладка заливається, а не товщає: інакше рядок смикається.
                            PoruchIcon(glyph: item.glyph, size: 22)
                                .overlay(alignment: .topTrailing) {
                                    // Бейдж поверх кута гліфа: число справ, не повідомлень.
                                    if item.badge > 0 {
                                        Text("\(min(item.badge, 99))").font(PoruchFont.overline).foregroundStyle(Palette.onBrand)
                                            .padding(.horizontal, 5).padding(.vertical, 1)
                                            .background(Palette.accent, in: Capsule())
                                            .offset(x: 10, y: -6)
                                    }
                                }
                            Text(item.label).font(PoruchFont.overline).lineLimit(1)
                        }
                        .foregroundStyle(selection == item.id ? Palette.ink : Palette.inkTertiary)
                        .frame(maxWidth: .infinity).frame(height: 42)
                        .background {
                            // Тонова пігулка під активним гліфом: стан видно й на відстані руки.
                            if selection == item.id { Capsule().fill(Palette.brandContainer) }
                        }
                    }
                    .buttonStyle(PressableStyle(pressedScale: 0.94))
                    .accessibilityLabel(item.badge > 0 ? "\(item.label), непрочитаних чатів: \(item.badge)" : item.label)
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
                // Тепле сяйво замість сірої тіні для єдиної завжди видимої дії.
                .shadow(color: Palette.accent.opacity(0.45), radius: 14, y: 6)
                .shadow(color: .black.opacity(0.16), radius: 5, y: 2)
        }
        .buttonStyle(PressableStyle(pressedScale: 0.94))
        .accessibilityLabel("Створити подію")
    }
}
