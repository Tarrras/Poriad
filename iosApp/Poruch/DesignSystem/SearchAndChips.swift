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
                    .submitLabel(.search).accessibilityLabel(Copy.a11y_search_events)
                if !text.isEmpty {
                    Button { text = "" } label: { PoruchIcon(glyph: PoruchIcons.closeCircle, size: 20).foregroundStyle(Palette.inkTertiary).tapTarget() }
                        .accessibilityLabel(Copy.clear_search)
                }
            }
            .padding(.horizontal, Space.lg).frame(height: 50)
            .background(Palette.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1).opacity(darkStroke))
            if let onFilters {
                IconPill(glyph: PoruchIcons.filters, label: Copy.filters, action: onFilters)
                    .overlay(alignment: .topTrailing) {
                        if activeFilters > 0 {
                            Text("\(activeFilters)").font(PoruchFont.overline).foregroundStyle(Palette.onBrand)
                                .frame(width: 18, height: 18).background(Palette.accentText, in: Circle()).offset(x: 2, y: -2)
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
    /// Текст зі спільного стану. Поле бере його при створенні й коли він змінився ззовні.
    let initial: String
    var activeFilters: Int = 0
    var onFilters: (() -> Void)?
    let onSettled: (String) -> Void

    @State private var text: String
    /// Що поле саме віддало нагору. Повернення цього ж значення — луна, а не зміна ззовні.
    @State private var sent: String

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
        _sent = State(initialValue: initial)
    }

    var body: some View {
        SearchField(text: $text, placeholder: placeholder, activeFilters: activeFilters, onFilters: onFilters)
            .onSettled(text, after: .milliseconds(searchSettle)) { sent = $0; onSettled($0) }
            // Текст може прийти ззовні («Усі» з головної несе запит на мапу): поле мусить його показати,
            // інакше фільтр діє невидимо. Власну луну пропускаємо, щоб не затерти літери, набрані поки вона йшла.
            .onChange(of: initial) { _, value in
                guard value != sent else { return }
                sent = value; text = value
            }
    }
}

/// Пауза після набору перед оновленням спільного стану.
private let searchSettle = 250

struct IconPill: View {
    @Environment(\.colorScheme) private var scheme
    let glyph: PoruchGlyph
    let label: String
    var selected: Bool = false
    var size: CGFloat = 48
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            PoruchIcon(glyph: glyph, size: 20)
                .foregroundStyle(selected ? Palette.onBrand : Palette.ink)
                .frame(width: size, height: size)
                .background {
                    if selected { Circle().fill(brandGradient) } else { Circle().fill(Palette.surface) }
                }
                .overlay(Circle().strokeBorder(Palette.hairline, lineWidth: selected || scheme == .light ? 0 : 1))
                .tapTarget()
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }
}

/// Крапка категорії: найменший носій її кольору.
struct CategoryDot: View {
    let category: EventCategory
    var size: CGFloat = 8
    var body: some View { Circle().fill(categoryInk(category)).frame(width: size, height: size) }
}

/// Чип: біла пігулка на сірому; обраний заливається чорнилом.
struct Chip: View {
    @Environment(\.colorScheme) private var scheme
    let label: String
    var glyph: PoruchGlyph?
    var dot: EventCategory?
    /// Гліф після підпису: шеврон каже, що чип відкриває вибір, а не перемикає фільтр.
    var trailingGlyph: PoruchGlyph?
    /// Скільки непрочитаних чатів у цьому розрізі.
    var badge: Int = 0
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.sm) {
                if let dot {
                    Circle().fill(selected ? Palette.onBrand : categoryInk(dot)).frame(width: 8, height: 8)
                } else if let glyph {
                    PoruchIcon(glyph: glyph, size: 15)
                        .foregroundStyle(selected ? Palette.onBrand : Palette.inkSecondary)
                }
                Text(label).font(PoruchFont.label)
                if let trailingGlyph {
                    PoruchIcon(glyph: trailingGlyph, size: 13)
                        .foregroundStyle(selected ? Palette.onBrand : Palette.inkSecondary)
                }
                if badge > 0 { CountBadge(count: badge) }
            }
            .foregroundStyle(selected ? Palette.onBrand : Palette.ink)
            // Найменша висота, а не стала: з великим текстом чип росте, а не випускає підпис за капсулу.
            .padding(.horizontal, Space.lg).padding(.vertical, Space.xs).frame(minHeight: 38)
            .background {
                if selected { Capsule().fill(brandGradient) } else { Capsule().fill(Palette.surface) }
            }
            .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: selected || scheme == .light ? 0 : 1))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(badge > 0 ? Copy.unread_messages_a11y("\(badge)") : "")
    }
}

/// «Стежити» / «Ви стежите» біля закладу чи організатора: чип-перемикач, обраний заливається, як усі чипи.
/// Гліф — дзвінок, бо пуш про нове і є суттю підписки. Стан приходить зі спільного шару, тап лише просить його змінити.
struct FollowPill: View {
    let following: Bool
    /// Лише дзвінок, для тісної шапки мапи; підпис читає VoiceOver.
    var iconOnly = false
    let action: () -> Void
    private var label: String { following ? Copy.following : Copy.follow }
    private var glyph: PoruchGlyph { following ? PoruchIcons.bellActive : PoruchIcons.bell }
    var body: some View {
        if iconOnly {
            IconPill(glyph: glyph, label: label, selected: following, size: 40, action: action)
                .accessibilityAddTraits(following ? .isSelected : [])
        } else {
            Chip(label: label, glyph: glyph, selected: following, action: action)
        }
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
                    // Великий шрифт стискає напис до 70 % і робить пункт вищим, а не обрізає «Реєстрац…».
                    Text(title).font(PoruchFont.button).lineLimit(1).minimumScaleFactor(0.7)
                        .foregroundStyle(index == selection ? Palette.ink : Palette.inkSecondary)
                        .padding(.horizontal, Space.sm)
                        .frame(maxWidth: .infinity).frame(minHeight: 40)
                        .background {
                            if index == selection {
                                Capsule().fill(Palette.surface).matchedGeometryEffect(id: "thumb", in: thumb)
                            }
                        }
                        // Ціль 44: два пункти поля відступу контейнера належать кнопці, а не порожнечі.
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(index == selection ? .isSelected : [])
            }
        }
        .padding(.horizontal, 4).padding(.vertical, 2)
        .background(Palette.brandContainer, in: Capsule())
        .motion(Motion.spring, value: selection)
    }
}

/// Плитка категорії: скруглений квадрат у пастелі категорії.
struct CategoryTile: View {
    let category: EventCategory
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
                // «Конференції» в 76 pt стискаються, а не обрізаються. Вище xLarge стиснення вже не рятує («Конфере…»),
                // тож підпис далі не росте, як у штампа; VoiceOver читає назву повністю.
                Text(categoryName(category)).font(PoruchFont.label).lineLimit(1).minimumScaleFactor(0.7)
                    .dynamicTypeSize(...DynamicTypeSize.xLarge)
                    .foregroundStyle(selected ? Palette.ink : Palette.inkSecondary)
            }.frame(width: 76)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(categoryName(category))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
