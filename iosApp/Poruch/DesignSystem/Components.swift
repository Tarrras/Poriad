import SwiftUI
import Shared

// ---- Пошук і чипи

struct SearchField: View {
    @Environment(\.colorScheme) private var scheme
    private var darkStroke: Double { scheme == .dark ? 1 : 0 }
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
            .padding(.horizontal, Space.lg).frame(height: 50)
            .background(Palette.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1).opacity(darkStroke))
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
    @Environment(\.colorScheme) private var scheme
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
                .overlay(Circle().strokeBorder(Palette.hairline, lineWidth: selected || scheme == .light ? 0 : 1))
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

/// Чип: біла пігулка на сірому; обраний заливається чорнилом.
struct Chip: View {
    @Environment(\.colorScheme) private var scheme
    let label: String
    var symbol: String?
    var dot: String?
    /// Гліф після підпису: шеврон каже, що чип відкриває вибір, а не перемикає фільтр.
    var trailingSymbol: String?
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
                if let trailingSymbol {
                    Image(systemName: trailingSymbol).font(.system(size: 10, weight: .bold))
                        .foregroundStyle(selected ? Palette.onBrand : Palette.inkSecondary)
                }
            }
            .foregroundStyle(selected ? Palette.onBrand : Palette.ink)
            .padding(.horizontal, Space.lg).frame(height: 38)
            .background {
                if selected { Capsule().fill(brandGradient) } else { Capsule().fill(Palette.surface) }
            }
            .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: selected || scheme == .light ? 0 : 1))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Сегментований перемикач-пігулка: тиха доріжка, біла пластина під обраним. Два-три рівноправні режими одного екрана.
struct SegmentedPill: View {
    let items: [String]
    let selection: Int
    let select: (Int) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var thumb
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, title in
                Button { if index != selection { select(index) } } label: {
                    Text(title).font(PoruchFont.button)
                        .foregroundStyle(index == selection ? Palette.ink : Palette.inkSecondary)
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background {
                            if index == selection {
                                Capsule().fill(Palette.surface).matchedGeometryEffect(id: "thumb", in: thumb)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(index == selection ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Palette.brandContainer, in: Capsule())
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85), value: selection)
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
                        in: RoundedRectangle(cornerRadius: Corner.md, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Corner.md, style: .continuous)
                            .strokeBorder(Palette.ink, lineWidth: selected ? 2 : 0)
                    )
                Text(categoryName(category)).font(PoruchFont.label).lineLimit(1)
                    .foregroundStyle(selected ? Palette.ink : Palette.inkSecondary)
            }.frame(width: 76)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(categoryName(category))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Картка категорії для сіток вибору (онбординг, редактор): пастель на всю картку, гліф угорі, назва внизу, позначка в кутку.
struct CategoryCard: View {
    let category: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    PoruchIcon(glyph: categoryGlyph(category), size: 24).foregroundStyle(categoryInk(category))
                    Spacer(minLength: 0)
                    ZStack {
                        Circle().fill(selected ? Palette.brand : Palette.surface.opacity(0.7))
                        if selected {
                            Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.onBrand)
                        }
                    }.frame(width: 20, height: 20)
                }
                Spacer(minLength: Space.md)
                Text(categoryName(category)).font(PoruchFont.label).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(Space.md).frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .background(categoryGradient(category), in: RoundedRectangle(cornerRadius: Corner.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Corner.md, style: .continuous).strokeBorder(Palette.ink, lineWidth: selected ? 2 : 0))
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
    /// Бейдж лежить на фото. Тонована напівпрозора пігулка на випадковому знімку не читалась:
    /// сірий текст на сірому. На фото — майже непрозора поверхня, чорнило й тінь, як у `SaveButton`.
    var onPhoto: Bool = false
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
            Text(text.uppercased()).font(PoruchFont.overline).kerning(1.0)
        }
        .foregroundStyle(onPhoto && (tone == .neutral || tone == .brand) ? Palette.ink : colors.1)
        .padding(.horizontal, Space.md).padding(.vertical, 5)
        .background {
            if onPhoto {
                Capsule().fill(Palette.surface.opacity(0.92))
                    .overlay(Capsule().strokeBorder(.black.opacity(0.06), lineWidth: 1))
                    .shadow(color: .black.opacity(0.22), radius: 6, y: 2)
            } else {
                Capsule().fill(toneGradient(colors.0, colors.1))
            }
        }
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
                // Блідіша за другорядну кнопку поруч: інакше «Назад» і неактивна «Далі» виглядали однаково.
                case (false, _): Capsule().fill(Palette.brandContainer.opacity(0.55))
                case (true, .some(let tone)): Capsule().fill(LinearGradient(colors: [tone.opacity(0.92), tone], startPoint: .top, endPoint: .bottom))
                case (true, .none): Capsule().fill(brandGradient)
                }
            }
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
            .background(Palette.brandContainer, in: Capsule())
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
    }
}

// ---- Структура

/// Заголовок секції читабельного розміру, як написано. Капітель лишається там, де несе дані.
struct SectionHeader: View {
    let title: String
    var actionLabel: String?
    var action: (() -> Void)?
    var body: some View {
        HStack {
            Text(title).font(PoruchFont.sectionTitle).kerning(-0.5).foregroundStyle(Palette.ink)
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
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: Corner.md, style: .continuous))
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
                    .background(Palette.surfaceMuted, in: RoundedRectangle(cornerRadius: Corner.xs, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(PoruchFont.cardName).foregroundStyle(Palette.ink).multilineTextAlignment(.leading)
                    Text(subtitle).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.onBrand)
                    .frame(width: 32, height: 32).background(Palette.brand, in: Circle())
            }
            .padding(Space.lg)
            .cardSurface()
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
                .background(Palette.surfaceMuted, in: RoundedRectangle(cornerRadius: Corner.xs, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased()).font(PoruchFont.overline).kerning(1.0).foregroundStyle(Palette.inkTertiary)
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
            Text(label.uppercased()).font(PoruchFont.overline).kerning(1.0).foregroundStyle(Palette.inkTertiary)
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
            // Біле поле на сірому полотні: `surfaceMuted` відрізнявся від полотна на два тони і поле зникало.
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Corner.sm, style: .continuous))
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
        }
        // Фото в накладці, а не в стосі: `scaledToFill` повідомляє розмір заповнення, і горизонтальний
        // знімок у високій обкладинці робив її ширшою за екран, розпираючи всю сторінку. Накладка
        // отримує розмір основи й не впливає на розкладку.
        .overlay {
            if let source = event.imageUrl, let url = URL(string: source), url.scheme == "https" {
                CachedImage(url: url, maxDimension: maxDimension)
                    .overlay(
                        LinearGradient(
                            colors: [.black.opacity(0.28), .clear, .black.opacity(0.12)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
            }
        }
        .clipped()
        .decorative()
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

/// Крапка категорії плюс її назва кольором категорії.
struct EventDescriptor: View {
    let event: Event
    var body: some View {
        HStack(spacing: Space.sm) {
            CategoryDot(category: event.category)
            Text(categoryName(event.category))
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
                    .frame(height: event.imageUrl == nil ? 120 : 200).frame(maxWidth: .infinity).clipped()
                    .overlay(alignment: .topLeading) {
                        if let badge = eventBadge(event, waitlisted: waitlisted) {
                            StatusBadge(text: badge.0, tone: badge.1, symbol: badge.2, onPhoto: true).padding(Space.sm)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if let onSave { SaveButton(saved: saved, action: onSave).padding(Space.sm) }
                    }
                VStack(alignment: .leading, spacing: Space.sm) {
                    Text(cardOverline(event)).font(PoruchFont.overline).kerning(1.0).foregroundStyle(Palette.inkTertiary)
                    Text(event.title).font(PoruchFont.cardName).kerning(-0.2).foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.leading).lineLimit(2)
                    EventDescriptor(event: event)
                    EventMeta(event: event)
                }.padding(Space.lg).frame(maxWidth: .infinity, alignment: .leading)
            }
            // Фото врівень із краєм картки, тому обрізаємо всю картку за її ж радіусом.
            .clipShape(RoundedRectangle(cornerRadius: Corner.lg, style: .continuous))
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
                Text(cardOverline(event)).font(PoruchFont.overline).kerning(1.0).foregroundStyle(Palette.inkTertiary)
                Text(event.title).font(PoruchFont.cardName).kerning(-0.2).foregroundStyle(Palette.ink)
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
                    Text(cardOverline(event)).font(PoruchFont.overline).kerning(1.0).foregroundStyle(Palette.inkTertiary)
                    Text(event.title).font(PoruchFont.cardName).kerning(-0.2).foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.leading).lineLimit(2)
                    if let badge = eventBadge(event) { StatusBadge(text: badge.0, tone: badge.1, symbol: badge.2) }
                    else { EventMeta(event: event, short: true) }
                }
                Spacer(minLength: 0)
                if let onSave { SaveButton(saved: saved, action: onSave) }
            }
            .padding(Space.md)
            .frame(height: mapCardHeight)
            .glassSurface(radius: Corner.lg)
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
            VStack(alignment: .leading, spacing: 0) {
                EventThumbnail(event: event, maxDimension: 240)
                    .frame(height: 120).frame(maxWidth: .infinity).clipped()
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(cardOverline(event)).font(PoruchFont.overline).kerning(1.0).foregroundStyle(Palette.inkTertiary)
                    Text(event.title).font(PoruchFont.cardName).kerning(-0.2).foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.leading).lineLimit(2, reservesSpace: true)
                    EventDescriptor(event: event)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.md)
            }
            .clipShape(RoundedRectangle(cornerRadius: Corner.lg, style: .continuous))
            .cardSurface()
            .opacity(event.isCancelled ? 0.6 : 1)
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .combine)
    }
}

// ---- Композиційні картки головної

/// Велика картка-афіша: обкладинка на всю висоту, текст на затемненні внизу. Одна на екран, для головного.
struct EventHeroCard: View {
    let event: Event
    let eyebrow: String
    var saved: Bool = false
    var onSave: (() -> Void)?
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            EventThumbnail(event: event, glyphSize: 56, maxDimension: 800)
                .frame(height: 360).frame(maxWidth: .infinity).clipped()
                .overlay(
                    LinearGradient(
                        stops: [.init(color: .clear, location: 0.3), .init(color: .black.opacity(0.55), location: 0.7),
                                .init(color: .black.opacity(0.85), location: 1)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text(eyebrow.uppercased()).font(PoruchFont.overline).kerning(1.0).foregroundStyle(.white.opacity(0.75))
                        Text(event.title).font(PoruchFont.title1).titleTracking().foregroundStyle(.white)
                            .multilineTextAlignment(.leading).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                        Text([cardOverline(event), categoryName(event.category)].joined(separator: " · "))
                            .font(PoruchFont.subhead).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                    }
                    .padding(Space.xl)
                }
                .overlay(alignment: .topTrailing) {
                    if let onSave { SaveButton(saved: saved, action: onSave).padding(Space.md) }
                }
                .overlay(alignment: .topLeading) {
                    if let badge = eventBadge(event) {
                        StatusBadge(text: badge.0, tone: badge.1, symbol: badge.2, onPhoto: true).padding(Space.lg)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Corner.xl, style: .continuous))
                .opacity(event.isCancelled ? 0.6 : 1)
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .combine)
    }
}

/// Широка картка горизонтальної стрічки: фото врівень із краєм, текст під ним. Сусідня визирає з-за краю.
struct EventRailCard: View {
    let event: Event
    var saved: Bool = false
    var onSave: (() -> Void)?
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                EventThumbnail(event: event, glyphSize: 32, maxDimension: 600)
                    .frame(height: 170).frame(maxWidth: .infinity).clipped()
                    .overlay(alignment: .topLeading) {
                        if let badge = eventBadge(event) {
                            StatusBadge(text: badge.0, tone: badge.1, symbol: badge.2, onPhoto: true).padding(Space.md)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if let onSave { SaveButton(saved: saved, action: onSave).padding(Space.sm) }
                    }
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(cardOverline(event)).font(PoruchFont.overline).kerning(1.0).foregroundStyle(Palette.inkTertiary)
                    Text(event.title).font(PoruchFont.cardName).kerning(-0.2).foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.leading).lineLimit(2, reservesSpace: true)
                    EventDescriptor(event: event)
                    EventMeta(event: event, short: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.lg)
            }
            .frame(width: 300)
            .clipShape(RoundedRectangle(cornerRadius: Corner.lg, style: .continuous))
            .cardSurface()
            .opacity(event.isCancelled ? 0.6 : 1)
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .combine)
    }
}

/// Швидка дія на пів ширини: надрядок, назва, гліф у кутку.
struct QuickActionCard: View {
    let eyebrow: String
    let title: String
    let symbol: String
    var filled = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Space.md) {
                Image(systemName: symbol).font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(filled ? Palette.onBrand : Palette.ink)
                    .frame(width: 40, height: 40)
                    .background(filled ? Palette.onBrand.opacity(0.14) : Palette.surfaceMuted, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(eyebrow.uppercased()).font(PoruchFont.overline).kerning(1.0)
                        .foregroundStyle(filled ? Palette.onBrand.opacity(0.7) : Palette.inkTertiary)
                    Text(title).font(PoruchFont.cardName).kerning(-0.2)
                        .foregroundStyle(filled ? Palette.onBrand : Palette.ink).lineLimit(1)
                }
            }
            .padding(Space.lg).frame(maxWidth: .infinity, alignment: .leading)
            .background {
                // Незалита картка — звичайна поверхня, з лінією по краю в темній темі, як усі картки поруч.
                if filled { RoundedRectangle(cornerRadius: Corner.lg, style: .continuous).fill(Palette.brand) }
                else { Color.clear.cardSurface() }
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("\(eyebrow): \(title)")
    }
}

/// Рядок групового списку: гліф, назва, підпис, справа значення й шеврон. Кілька рядків збирає `GroupedRows`.
struct LinkRow: View {
    let symbol: String
    let title: String
    var subtitle: String? = nil
    var value: String?
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.md) {
                Image(systemName: symbol).font(.system(size: 17, weight: .medium)).foregroundStyle(Palette.ink)
                    .frame(width: 40, height: 40).background(Palette.surfaceMuted, in: RoundedRectangle(cornerRadius: Corner.xs, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(PoruchFont.cardName).kerning(-0.2).foregroundStyle(Palette.ink).multilineTextAlignment(.leading)
                    if let subtitle {
                        Text(subtitle).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary).multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: Space.sm)
                if let value {
                    Text(value).font(PoruchFont.title2).foregroundStyle(Palette.ink).monospacedDigit()
                }
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.inkTertiary)
            }
            .padding(Space.lg).contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(pressedScale: 1))
        .accessibilityElement(children: .combine)
    }
}

/// Біла картка з рядками, розділеними лінією від тексту, а не від краю.
struct GroupedRows<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .cardSurface()
    }
}

/// Кругла дія з підписом під нею: ряд таких — панель дій на деталях.
struct RoundAction<Label: View>: View {
    let title: String
    var enabled = true
    @ViewBuilder var label: Label
    var body: some View {
        VStack(spacing: Space.sm) {
            label.font(.system(size: 19, weight: .semibold)).foregroundStyle(enabled ? Palette.ink : Palette.inkTertiary)
                .frame(width: 56, height: 56).background(Palette.surface, in: Circle())
            Text(title).font(PoruchFont.label).foregroundStyle(enabled ? Palette.ink : Palette.inkTertiary).lineLimit(1)
        }.frame(maxWidth: .infinity)
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

/// Плаваючий скляний таббар; під активним пунктом тонова пігулка.
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
            .glassSurface(radius: 32)
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
                .lifted(Elevation.overlay)
        }
        .buttonStyle(PressableStyle(pressedScale: 0.94))
        .accessibilityLabel("Створити подію")
    }
}
