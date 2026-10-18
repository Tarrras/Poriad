import SwiftUI
import Shared
import Lottie
import AmplitudeSessionReplay

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

// ---- Бейджі й кнопки

enum BadgeTone { case brand, success, accent, danger, neutral }

struct StatusBadge: View {
    let text: String
    var tone: BadgeTone = .neutral
    var glyph: PoruchGlyph?
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
            if let glyph { PoruchIcon(glyph: glyph, size: 13) }
            Text(text.uppercased()).font(PoruchFont.overline).kerning(1.0)
        }
        .foregroundStyle(onPhoto && (tone == .neutral || tone == .brand) ? Palette.ink : colors.1)
        // Росте з текстом, але не вище Accessibility 1: на фото плашка інакше закривала пів постера.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
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

/// Питання знизу, як `PoruchSheet` на Android: заголовок із засічками, пояснення, головна й другорядна дія.
/// Змах униз — те саме, що другорядна дія: `onDismiss` у `.sheet` викликає її, якщо кнопку не натиснули.
struct PromptSheet: View {
    let title: String
    let message: String
    let primary: String
    var secondary: String?
    let onPrimary: () -> Void
    var onSecondary: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var height: CGFloat = 320
    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text(title).font(PoruchFont.brandTitle2).kerning(-0.2).foregroundStyle(Palette.ink)
            Text(message).font(PoruchFont.bodyText).foregroundStyle(Palette.inkSecondary).padding(.bottom, Space.sm)
            PrimaryButton(title: primary) { dismiss(); onPrimary() }
            if let secondary { SecondaryButton(title: secondary) { dismiss(); onSecondary() } }
        }
        .padding(.horizontal, Space.page).padding(.top, Space.xl).padding(.bottom, Space.section)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.canvas)
    }
}

/// Кнопки — зібрані прямокутники з кутом квитка, а не пігулки: пігулками лишились чипи й бейджі.
let buttonShape = RoundedRectangle(cornerRadius: Corner.md, style: .continuous)

struct PrimaryButton: View {
    let title: String
    var glyph: PoruchGlyph?
    /// SF Symbol лише для чужих знаків, яких у наборі бути не може (логотип Apple).
    var symbol: String?
    var tone: Color?
    var loading: Bool = false
    var enabled: Bool = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.sm) {
                if loading { ProgressView().tint(enabled ? Palette.onBrand : Palette.inkTertiary) }
                else if let glyph { PoruchIcon(glyph: glyph, size: 18) }
                else if let symbol { Image(systemName: symbol).font(.system(size: 15, weight: .semibold)) }
                // Великий шрифт переносить напис, а не обрізає: кнопка росте від 52 pt.
                Text(title).font(PoruchFont.button).lineLimit(2).multilineTextAlignment(.center)
            }
            .foregroundStyle(enabled ? Palette.onBrand : Palette.inkTertiary)
            .padding(.horizontal, Space.xxl).padding(.vertical, Space.sm).frame(minHeight: 52).frame(maxWidth: .infinity)
            .background {
                switch (enabled, tone) {
                // Блідіша за другорядну кнопку поруч: інакше «Назад» і неактивна «Далі» виглядали однаково.
                case (false, _): buttonShape.fill(Palette.brandContainer.opacity(0.55))
                case (true, .some(let tone)): buttonShape.fill(tone)
                case (true, .none): buttonShape.fill(brandGradient)
                }
            }
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled || loading)
    }
}

struct SecondaryButton: View {
    let title: String
    var glyph: PoruchGlyph?
    /// SF Symbol лише для чужих знаків, яких у наборі бути не може (логотип Apple).
    var symbol: String?
    var tone: Color?
    var enabled: Bool = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.sm) {
                if let glyph { PoruchIcon(glyph: glyph, size: 18) }
                else if let symbol { Image(systemName: symbol).font(.system(size: 15, weight: .semibold)) }
                Text(title).font(PoruchFont.button).lineLimit(2).multilineTextAlignment(.center)
            }
            .foregroundStyle(enabled ? tone ?? Palette.ink : Palette.inkTertiary)
            .padding(.horizontal, Space.xxl).padding(.vertical, Space.sm).frame(minHeight: 52).frame(maxWidth: .infinity)
            .background(Palette.brandContainer, in: buttonShape)
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
        // Заголовок і дія не влазять в один рядок (великий шрифт) — дія стає під заголовком, а не стискає обох у два вузькі стовпці.
        ViewThatFits(in: .horizontal) {
            HStack {
                heading
                Spacer(minLength: Space.sm)
                actionButton(stacked: false)
            }
            VStack(alignment: .leading, spacing: Space.xs) {
                heading
                actionButton(stacked: true)
            }
        }
    }

    private var heading: some View {
        Text(title).font(PoruchFont.brandTitle2).kerning(-0.2).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
    }

    /// Праворуч дію впізнають за місцем, як «Усі 246»; під заголовком вона читалась би як підзаголовок, тож бере шеврон.
    @ViewBuilder private func actionButton(stacked: Bool) -> some View {
        if let actionLabel, let action {
            Button(action: action) {
                HStack(spacing: Space.xs) {
                    Text(actionLabel)
                    if stacked { PoruchIcon(glyph: PoruchIcons.chevronRight, size: 13) }
                }
            }
            .font(PoruchFont.label).foregroundStyle(Palette.ink)
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
                    PoruchIcon(glyph: PoruchIcons.chevronLeft, size: 19).foregroundStyle(Palette.ink)
                        .frame(width: 40, height: 40).background(Palette.surface, in: Circle()).tapTarget()
                }.buttonStyle(PressableStyle()).accessibilityLabel(Copy.back)
            }
            Text(title).font(PoruchFont.brandTitle1).kerning(-0.4).foregroundStyle(Palette.ink)
            Spacer(minLength: 0)
            trailing
        }.padding(.horizontal, Space.page).padding(.vertical, Space.md)
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, back: (() -> Void)? = nil) { self.init(title: title, back: back) { EmptyView() } }
}

/// Фірмова Lottie-анімація з Assets: `<name>Light` або `<name>Dark` за темою. Малюнки — tools/generate_lottie.py.
struct BrandAnimation: View {
    let name: String
    var loop = true
    var onFinish: (() -> Void)?
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        LottieView(animation: .asset(name + (scheme == .dark ? "Dark" : "Light")))
            .playing(loopMode: loop ? .loop : .playOnce)
            .animationDidFinish { _ in onFinish?() }
    }
}

/// Лоадер екрана чи секції: шпилька з іконки підстрибує. Кнопки й дрібні підвантаження лишаються з системним.
struct PoruchLoader: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        if reduceMotion { ProgressView() } else { BrandAnimation(name: "Loader").frame(width: 56, height: 56) }
    }
}

struct EmptyState: View {
    let glyph: PoruchGlyph
    let title: String
    let message: String
    var compact: Bool = false
    var actionLabel: String?
    var action: (() -> Void)?
    var body: some View {
        VStack(spacing: compact ? Space.sm : Space.md) {
            BlankTicket(glyph: glyph, compact: compact).padding(.bottom, compact ? 0 : Space.sm)
            Text(title).font(compact ? PoruchFont.brandTitle3 : PoruchFont.brandTitle2).foregroundStyle(Palette.ink).multilineTextAlignment(.center)
            Text(message).font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary).multilineTextAlignment(.center)
            if let actionLabel, let action {
                PrimaryButton(title: actionLabel, action: action).fixedSize(horizontal: true, vertical: false).padding(.top, Space.sm)
            }
        }.padding(compact ? Space.md : Space.xxl).frame(maxWidth: .infinity)
    }
}

/// Порожній квиток над порожнім станом: пунктирний контур, два незадруковані рядки й гліф на сірому корінці.
private struct BlankTicket: View {
    let glyph: PoruchGlyph
    var compact = false
    var body: some View {
        Ticket(
            stubColor: Palette.surfaceMuted, stubLength: compact ? 44 : 56, radius: Corner.sm,
            outline: (Palette.inkTertiary.opacity(0.6), StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        ) {
            VStack(alignment: .leading, spacing: 6) {
                Capsule().fill(Palette.hairline).frame(width: compact ? 48 : 72, height: 6)
                Capsule().fill(Palette.hairline).frame(width: compact ? 32 : 44, height: 6)
            }
            .padding(.horizontal, Space.md)
            .frame(maxWidth: .infinity, minHeight: compact ? 52 : 72, alignment: .leading)
        } stub: {
            PoruchIcon(glyph: glyph, size: compact ? 18 : 22).foregroundStyle(Palette.inkSecondary)
        }
        .frame(width: compact ? 132 : 184)
        .decorative()
    }
}

struct BannerCard: View {
    let title: String
    /// Без підпису банер тонкий: гліф, один рядок і стрілка.
    var subtitle: String?
    var glyph: PoruchGlyph = PoruchIcons.sparkle
    let action: () -> Void
    private var slim: Bool { subtitle == nil }
    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.md) {
                PoruchIcon(glyph: glyph, size: 20).foregroundStyle(Palette.ink)
                    .frame(width: slim ? 36 : 44, height: slim ? 36 : 44)
                    .background(Palette.surfaceMuted, in: RoundedRectangle(cornerRadius: Corner.xs, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(PoruchFont.cardName).foregroundStyle(Palette.ink).multilineTextAlignment(.leading)
                    if let subtitle {
                        Text(subtitle).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary).multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
                PoruchIcon(glyph: PoruchIcons.arrowRight, size: 16).foregroundStyle(Palette.onBrand)
                    .frame(width: slim ? 28 : 32, height: slim ? 28 : 32).background(Palette.brand, in: Circle())
            }
            .padding(.horizontal, Space.lg).padding(.vertical, slim ? Space.md : Space.lg)
            .cardSurface()
        }.buttonStyle(PressableStyle())
    }
}

/// Фото людини або перша літера імені, поки фото нема чи воно ще їде.
struct Avatar: View {
    let name: String
    let url: String?
    var size: CGFloat = 32
    var body: some View {
        ZStack {
            Circle().fill(Palette.surfaceMuted)
            Text(name.trimmingCharacters(in: .whitespaces).prefix(1).uppercased())
                .font(size >= 56 ? PoruchFont.title1 : PoruchFont.label).foregroundStyle(Palette.inkSecondary)
            if let url, let source = URL(string: url), source.scheme == "https" {
                // Той самий кеш, що в картках: `AsyncImage` нічого не пам'ятає.
                CachedImage(url: source, maxDimension: size).clipShape(Circle())
            }
        }
        .frame(width: size, height: size)
        // Обличчя людей не йдуть у Session Replay: маска `conservative` ховає лише текст.
        .amp_setBlocked(true)
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
                Avatar(name: attendee.name, url: attendee.avatarUrl, size: size)
                .overlay(Circle().strokeBorder(Palette.surface, lineWidth: 2))
                .offset(x: CGFloat(-index * 10))
                .zIndex(Double(shown.count - index))
            }
            if total > shown.count {
                Text("+\(total - shown.count)").font(PoruchFont.label).foregroundStyle(Palette.inkSecondary)
                    .offset(x: CGFloat(-shown.count * 10 + 4))
            }
        }.accessibilityElement(children: .ignore).accessibilityLabel(Copy.a11y_attendees_count("\(total)"))
    }
}

struct MetaLine: View {
    let glyph: PoruchGlyph
    let text: String
    var tone: Color?
    var body: some View {
        HStack(spacing: Space.sm) {
            PoruchIcon(glyph: glyph, size: 15).foregroundStyle(tone ?? Palette.inkTertiary).frame(width: 15)
            Text(text).font(PoruchFont.caption).foregroundStyle(tone ?? Palette.inkSecondary).lineLimit(1)
        }
    }
}

struct InfoRow: View {
    let glyph: PoruchGlyph
    let label: String
    let value: String
    var body: some View {
        HStack(alignment: .top, spacing: Space.md) {
            PoruchIcon(glyph: glyph, size: 18).foregroundStyle(Palette.inkSecondary)
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
            // Підпис — назва самого поля для VoiceOver, а не окрема зупинка перед ним: з порожньою назвою
            // заповнене поле озвучувало лише значення, без того, що це за поле.
            Text(label.uppercased()).font(PoruchFont.overline).kerning(1.0).foregroundStyle(Palette.inkTertiary)
                .accessibilityHidden(true)
            HStack(spacing: Space.sm) {
                Group {
                    if secure {
                        SecureField(label, text: $text, prompt: Text(placeholder).foregroundStyle(Palette.inkTertiary))
                    } else if multiline {
                        TextField(label, text: $text, prompt: Text(placeholder).foregroundStyle(Palette.inkTertiary), axis: .vertical)
                            .lineLimit(4...10)
                    } else {
                        TextField(label, text: $text, prompt: Text(placeholder).foregroundStyle(Palette.inkTertiary))
                    }
                }
                .font(PoruchFont.bodyText).foregroundStyle(Palette.ink).tint(Palette.ink).textFieldStyle(.plain)
                .accessibilityHint(hint ?? "")
                trailing
            }
            // Висота вміщує 44 pt ціль кінцевого контролу, не переростаючи сусіднє поле.
            .padding(.horizontal, Space.lg)
            .padding(.vertical, multiline ? Space.md : 0)
            .frame(minHeight: 56, alignment: multiline ? .top : .center)
            // Біле поле на сірому полотні: `surfaceMuted` відрізнявся від полотна на два тони і поле зникало.
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Corner.sm, style: .continuous))
            if let hint {
                // Читається підказкою поля, а не окремою зупинкою.
                Text(hint).font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary).accessibilityHidden(true)
            }
        }
    }
}

/// Дата народження в рамці поля: повна дата словами, тап розгортає барабан. Компактний `DatePicker`
/// без мітки висів з порожнім відступом і писав рік двома цифрами. Без значення, доки людина дату не
/// обере: правило 18+ не проходить саме. Барабан відкривається на найпізнішій дозволеній даті, як календар на Android.
struct BirthDateField: View {
    @Binding var date: Date?
    let range: ClosedRange<Date>
    @State private var open = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                if date == nil { date = range.upperBound }
                withMotion { open.toggle() }
            } label: {
                HStack(spacing: Space.sm) {
                    Text(date?.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "uk_UA"))) ?? Copy.birth_date_placeholder)
                        .font(PoruchFont.bodyText).foregroundStyle(date == nil ? Palette.inkTertiary : Palette.ink)
                    Spacer(minLength: 0)
                    PoruchIcon(glyph: PoruchIcons.calendar, size: 18)
                        .foregroundStyle(open ? Palette.brand : Palette.inkSecondary)
                }
                .padding(.horizontal, Space.lg).frame(minHeight: 56).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(open ? Copy.a11y_collapse_dates : Copy.a11y_change_date)
            if open {
                DatePicker("", selection: Binding(get: { date ?? range.upperBound }, set: { date = $0 }), in: range, displayedComponents: .date)
                    .datePickerStyle(.wheel).labelsHidden()
                    .environment(\.locale, Locale(identifier: "uk_UA"))
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            }
        }
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Corner.sm, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Corner.sm, style: .continuous))
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
    /// Велика рамка `scaledToFill`: `maxDimension` — найкоротша сторона. Див. `CachedImage.fill`.
    var fill = false
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
                CachedImage(url: url, maxDimension: maxDimension, fill: fill)
                    .overlay(
                        LinearGradient(
                            colors: [.black.opacity(0.28), .clear, .black.opacity(0.12)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    // `clipped` ріже лише малюнок: вертикальне фото в `scaledToFill` виходить за картку
                    // й ловить дотики над сусідами — тап по назві відкривав наступну подію, поле пошуку глухло.
                    .allowsHitTesting(false)
            }
        }
        .clipped()
        .decorative()
    }
}

/// Стан події словами: скасовано, знято, а для кімнати — «ви йдете», запит, черга, місця. Без підпису джерела афіші.
func eventState(_ event: Event, waitlisted: Bool = false) -> (String, BadgeTone, PoruchGlyph?)? {
    if event.isCancelled { return (Copy.cancelled_short, .danger, nil) }
    if let listing = event.listing { return listing.isWithdrawn ? (Copy.listing_withdrawn, .neutral, nil) : nil }
    guard let room = event.gathering else { return nil }
    // Місця й «ви йдете» після кінця нічого не кажуть: рядок покаже категорію.
    if event.hasEnded(now: nowInstant()) { return nil }
    if room.joined { return (Copy.going, .success, PoruchIcons.check) }
    if room.awaitingApproval { return (Copy.request_pending, .accent, PoruchIcons.queue) }
    if waitlisted { return (Copy.in_queue, .accent, PoruchIcons.queue) }
    if room.isFull { return (Copy.full, .neutral, nil) }
    if room.isScarce { return (Copy.seats_left_short("\(room.seatsLeft)"), .accent, nil) }
    return nil
}

/// Подія від людини, а не з афіші: підпис походження, пара до «Афіша · джерело». Стан кімнати («Ви йдете», «Лишилось 2») важливіший.
func communityBadge(_ event: Event) -> (String, BadgeTone, PoruchGlyph?)? {
    event.gathering == nil ? nil : (Copy.from_people, .neutral, PoruchIcons.social)
}

/// Рядок стану над карткою. Афіша завжди підписана джерелом (docs/event-ingestion.md §8); місця лише в кімнати.
func eventBadge(_ event: Event, waitlisted: Bool = false) -> (String, BadgeTone, PoruchGlyph?)? {
    if let state = eventState(event, waitlisted: waitlisted) { return state }
    guard let listing = event.listing else { return nil }
    return (Copy.listing_badge("\(listing.sourceName)"), .neutral, nil)
}

/// Рядок під назвою: учасники для кімнати, ціна для афіші.
struct EventMeta: View {
    let event: Event
    var short = false
    var body: some View {
        if let room = event.gathering {
            MetaLine(
                glyph: PoruchIcons.social,
                text: short ? Copy.attendees_short("\(room.attendeeCount)", "\(room.capacity)") : Copy.attendees("\(room.attendeeCount)", "\(room.capacity)")
            )
        } else if let listing = event.listing {
            MetaLine(glyph: PoruchIcons.ticket, text: listingPrice(listing))
        }
    }
}

/// Крапка категорії плюс її назва кольором категорії.
struct EventDescriptor: View {
    let event: Event
    /// Місто перед адресою: у видачі з різних міст сама адреса не каже, де це. Першим, бо хвіст
    /// адреси, де місто буває, обрізається.
    var withCity = false
    /// Місце першим, а категорія — лише крапкою її кольору: на постері назва закладу важливіша за жанр, який і так каже афіша.
    /// Жанр лишається в підписі для VoiceOver.
    var placeFirst = false
    private var place: String { eventPlace(event, withCity: withCity) }
    var body: some View {
        if placeFirst {
            row.accessibilityElement(children: .ignore)
                .accessibilityLabel([categoryName(event.category), place].filter { !$0.isEmpty }.joined(separator: ", "))
        } else {
            row
        }
    }
    private var row: some View {
        HStack(spacing: Space.sm) {
            CategoryDot(category: event.category)
            if placeFirst {
                Text(place.isEmpty ? categoryName(event.category) : place)
                    .font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary).lineLimit(1)
            } else {
                Text(categoryName(event.category))
                    .font(PoruchFont.descriptor).foregroundStyle(categoryInk(event.category)).lineLimit(1)
                Text(place.isEmpty ? "" : "· " + place)
                    .font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary).lineLimit(1)
            }
        }
    }
}

/// Підпис місця: назва закладу, коли є, інакше адреса чи місто. З `withCity` — місто першим,
/// якщо підпис із нього ще не починається.
func eventPlace(_ event: Event, withCity: Bool) -> String {
    let place = event.placeLabel
    guard withCity, !event.city.isEmpty, place != event.city, !place.hasPrefix(event.city + ",") else { return place }
    return place.isEmpty ? event.city : "\(event.city), \(place)"
}

struct SaveButton: View {
    let saved: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            PoruchIcon(glyph: saved ? PoruchIcons.bookmarkFilled : PoruchIcons.bookmark, size: 20)
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
        .accessibilityLabel(saved ? Copy.unsave : Copy.save)
    }
}

/// Картка стрічки: фото, надрядок дати, назва, рядок опису.
struct EventCard: View {
    let event: Event
    var saved: Bool = false
    var waitlisted: Bool = false
    var withCity = false
    var onSave: (() -> Void)?
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Ticket(stubColor: ticketStub(event), punched: event.hasEnded(now: nowInstant())) {
                VStack(alignment: .leading, spacing: 0) {
                    // Фото врівень із краєм квитка; без фото обкладинки нема — квиток і так кольоровий.
                    if event.imageUrl != nil {
                        EventThumbnail(event: event, maxDimension: 420)
                            .frame(height: 180).frame(maxWidth: .infinity).clipped()
                            .overlay(alignment: .topLeading) {
                                if let badge = eventBadge(event, waitlisted: waitlisted) {
                                    TicketStamp(text: badge.0, tone: badge.1, glyph: badge.2, onFill: true).padding(Space.md)
                                }
                            }
                    }
                    VStack(alignment: .leading, spacing: Space.sm) {
                        if event.imageUrl == nil, let badge = eventBadge(event, waitlisted: waitlisted) {
                            TicketStamp(text: badge.0, tone: badge.1, glyph: badge.2)
                        }
                        Text(event.displayTitle).font(PoruchFont.brandTitle3).foregroundStyle(Palette.ink)
                            .multilineTextAlignment(.leading).lineLimit(2)
                        EventDescriptor(event: event, withCity: withCity)
                        if let artists = artistsLine(event) { MetaLine(glyph: PoruchIcons.person, text: artists) }
                        if event.gathering == nil { EventMeta(event: event) }
                    }.padding(Space.lg).frame(maxWidth: .infinity, alignment: .leading)
                }
            } stub: {
                VStack(spacing: 0) {
                    if let onSave { SaveButton(saved: saved, action: onSave).padding(.top, Space.sm) }
                    Spacer(minLength: Space.md)
                    StubTime(event: event)
                    Spacer(minLength: Space.md)
                }
            }
        }
        .buttonStyle(PressableStyle())
        .ticketAccessibility(event, state: eventBadge(event, waitlisted: waitlisted)?.0, saved: saved, onSave: onSave)
    }
}

/// Компактний рядок списку: квадратне превʼю, назва, опис.
/// Число на акцентній пігулці: бейдж вкладки, рядка й чипа однаковий.
struct CountBadge: View {
    let count: Int
    var body: some View {
        Text("\(min(count, 99))").font(PoruchFont.overline).foregroundStyle(Palette.onBrand)
            .padding(.horizontal, 5).padding(.vertical, 1)
            // Тло — `accentText`: білий дрібний текст на самому `accent` давав лише 3,75:1.
            .background(Palette.accentText, in: Capsule())
            .accessibilityHidden(true)
    }
}

struct EventRow: View {
    let event: Event
    /// Непрочитані повідомлення чату: той самий бейдж, що на вкладці, — видно, куди він веде.
    var unread: Int = 0
    var waitlisted = false
    /// Рядок замість статусу й категорії: «Ваша оцінка ★ 5».
    var note: String? = nil
    /// Без шеврона, коли праворуч стоїть власна дія рядка.
    var chevron = true
    /// Статус замість `eventBadge`: «2 запити на участь» у своїй події.
    var status: (String, BadgeTone, PoruchGlyph?)? = nil
    var body: some View {
        HStack(spacing: Space.md) {
            StubTile(event: event)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(event.displayTitle).font(PoruchFont.brandTitle3).foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.leading).lineLimit(2)
                if let note { Text(note).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary).lineLimit(1) }
                else {
                    // Жанр і місце — завжди; штамп — лише коли з квитком щось сталось. Джерело афіші — тихим підписом,
                    // а не штампом: штамп «Афіша · Concert.ua» витісняв жанр і місце з усіх рядків афіші.
                    if let badge = status ?? eventState(event, waitlisted: waitlisted) {
                        TicketStamp(text: badge.0, tone: badge.1, glyph: badge.2).padding(.top, 2)
                    }
                    EventDescriptor(event: event)
                    if let listing = event.listing, !listing.isWithdrawn {
                        Text(Copy.listing_badge("\(listing.sourceName)")).font(PoruchFont.overline)
                            .foregroundStyle(Palette.inkTertiary).lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
            if unread > 0 { CountBadge(count: unread) }
            if chevron {
                PoruchIcon(glyph: PoruchIcons.chevronRight, size: 15).foregroundStyle(Palette.inkTertiary)
            }
        }
        .padding(.vertical, Space.md)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore).accessibilityLabel(ticketA11yLabel(event, state: note ?? (status ?? eventBadge(event, waitlisted: waitlisted))?.0))
        .accessibilityValue(unread > 0 ? Copy.unread_messages_a11y("\(unread)") : "")
    }
}

/// Відступ лінії між рядками видачі пошуку: від тексту, а не від краю.
let resultRowInset: CGFloat = Space.lg + 56 + Space.md

/// Рядок видачі пошуку: обкладинка категорії, дата, назва й «категорія · місце · ціна»; справа —
/// стан кімнати. Кілька рядків збирає `GroupedRows`. Афіша підписана джерелом окремим рядком:
/// атрибуція на картці обов'язкова (docs/event-ingestion.md §8).
struct EventResultRow: View {
    let event: Event
    var waitlisted = false
    /// Назвати місто в підписі: видача з різних міст.
    var withCity = false
    /// Nil — рядок без власної кнопки, для `NavigationLink`: вкладена кнопка забрала б тап.
    var action: (() -> Void)?

    private var subtitle: String {
        var parts = [categoryName(event.category)]
        let place = eventPlace(event, withCity: withCity)
        if !place.isEmpty { parts.append(place) }
        // Невідому ціну не пишемо: «ціну вкаже джерело» посеред рядка нічого не каже.
        if let listing = event.listing, listing.isFree?.boolValue == true || listing.priceMin != nil {
            let price = listingPrice(listing)
            parts.append(price.prefix(1).lowercased() + price.dropFirst())
        }
        return parts.joined(separator: " · ")
    }

    /// Лише те, що міняє рішення: скасування, зняття, стан кімнати. Джерело афіші — окремим рядком.
    private var badge: (String, BadgeTone, PoruchGlyph?)? {
        if event.isCancelled { return (Copy.cancelled_short, .danger, nil) }
        if event.listing?.isWithdrawn == true { return (Copy.listing_withdrawn, .neutral, nil) }
        guard let room = event.gathering, !event.hasEnded(now: nowInstant()) else { return nil }
        if room.joined { return (Copy.going, .success, PoruchIcons.check) }
        if waitlisted { return (Copy.in_queue, .accent, PoruchIcons.queue) }
        if room.isFull { return (Copy.full, .neutral, nil) }
        let seats = Int(room.seatsLeft)
        if room.isScarce { return (Copy.seats_short(seats), .accent, nil) }
        return nil
    }

    var body: some View {
        if let action {
            Button(action: action) { row }
                .buttonStyle(PressableStyle(pressedScale: 1))
                .accessibilityElement(children: .ignore).accessibilityLabel(ticketA11yLabel(event, state: badge?.0))
        } else {
            row.accessibilityElement(children: .ignore).accessibilityLabel(ticketA11yLabel(event, state: badge?.0))
        }
    }

    private var row: some View {
        HStack(spacing: Space.md) {
            StubTile(event: event, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.displayTitle).font(PoruchFont.brandTitle3).kerning(-0.1).foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.leading).lineLimit(2)
                Text(subtitle).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary).lineLimit(1)
                if let artists = artistsLine(event) {
                    Text(artists).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary).lineLimit(1)
                }
                if let listing = event.listing {
                    let source = Copy.listing_badge("\(listing.sourceName)")
                    Text(source).font(PoruchFont.overline).foregroundStyle(Palette.inkTertiary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let badge { TicketStamp(text: badge.0, tone: badge.1, glyph: badge.2) }
        }
        .padding(.horizontal, Space.lg).padding(.vertical, Space.md)
        .contentShape(Rectangle())
    }
}

/// Склад для картки одним рядком: до трьох імен, ведучий окремо («· ведучий Дмитро»), решта «та ще N». Nil — артистів нема.
/// Імена в картці не тапаються: вся картка вже кнопка, тапабельні чипи лише в деталях. Слова ті самі, що в Android `Components.kt`.
func artistsLine(_ event: Event) -> String? {
    let shown = event.cardArtists
    guard !shown.isEmpty else { return nil }
    let performers = shown.filter { $0.role != .host }.map(\.name).joined(separator: ", ")
    let hosts = shown.filter { $0.role == .host }.map(\.name).joined(separator: ", ")
    let line = [performers.isEmpty ? nil : performers, hosts.isEmpty ? nil : Copy.artist_line_host("\(hosts)")].compactMap { $0 }.joined(separator: " · ")
    let more = Int(event.moreArtists)
    return more > 0 ? Copy.digest_more("\(line)", "\(more)") : line
}

/// Вид словом, лише коли він відомий і не людина: `person` без підпису.
func artistKindLabel(_ kind: ArtistKind?) -> String? {
    switch kind {
    case .group: return Copy.artist_kind_group
    case .show: return Copy.artist_kind_show
    case .company: return Copy.artist_kind_company
    default: return nil
    }
}

/// Рядок артиста в пошуку: піктограма людини, ім'я й скільки подій попереду. Тап веде на екран артиста стеком.
struct ArtistRow: View {
    let artist: ArtistHit

    private var subtitle: String {
        let upcoming = Int(artist.upcoming)
        return [artistKindLabel(artist.kind), Copy.place_upcoming(upcoming)]
            .compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        NavigationLink(value: ArtistRoute(id: artist.id, name: artist.name, kind: artist.kind)) {
            HStack(spacing: Space.md) {
                PoruchIcon(glyph: PoruchIcons.person, size: 20).foregroundStyle(Palette.ink)
                    .frame(width: 40, height: 40)
                    .background(Palette.surfaceMuted, in: RoundedRectangle(cornerRadius: Corner.xs, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(artist.name).font(PoruchFont.brandTitle3).kerning(-0.1).foregroundStyle(Palette.ink).lineLimit(1)
                    Text(subtitle).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.lg).padding(.vertical, Space.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(pressedScale: 1))
        .accessibilityElement(children: .combine)
    }
}

/// Секція «Артисти» у видачі пошуку під «Місцями»: до п'яти рядків.
struct ArtistsGroup: View {
    let artists: [ArtistHit]
    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            GroupLabel(title: Copy.search_artists_group)
            GroupedRows {
                ForEach(Array(artists.prefix(Int(DiscoveryRules.shared.ARTISTS_LIMIT)).enumerated()), id: \.element.id) { position, artist in
                    if position > 0 { Divider().overlay(Palette.hairline).padding(.leading, Space.lg + 40 + Space.md) }
                    ArtistRow(artist: artist)
                }
            }
        }
    }
}

/// Рядок закладу в пошуку: піктограма місця, назва, адреса й скільки подій попереду.
struct PlaceRow: View {
    let place: Place
    var withCity = false
    let action: () -> Void

    private var subtitle: String {
        let address = withCity && !place.city.isEmpty && !place.address.contains(place.city)
            ? [place.city, place.address].filter { !$0.isEmpty }.joined(separator: ", ")
            : place.address
        let upcoming = Int(place.upcoming)
        return [address, Copy.place_upcoming(upcoming)]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.md) {
                PoruchIcon(glyph: PoruchIcons.pin, size: 20).foregroundStyle(Palette.ink)
                    .frame(width: 40, height: 40)
                    .background(Palette.surfaceMuted, in: RoundedRectangle(cornerRadius: Corner.xs, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name).font(PoruchFont.brandTitle3).kerning(-0.1).foregroundStyle(Palette.ink).lineLimit(1)
                    Text(subtitle).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary)
                        .multilineTextAlignment(.leading).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.lg).padding(.vertical, Space.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(pressedScale: 1))
        .accessibilityElement(children: .combine)
    }
}

/// Підпис над `GroupedRows` капітеллю: «Події · 7», «Місця». Праворуч — необов'язкова дія.
struct GroupLabel: View {
    let title: String
    var actionLabel: String?
    var action: (() -> Void)?
    var body: some View {
        HStack {
            Text(title.uppercased(with: Locale(identifier: "uk_UA"))).font(PoruchFont.overline).kerning(1.0).foregroundStyle(Palette.inkTertiary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Space.sm)
            if let actionLabel, let action {
                Button(actionLabel, action: action).font(PoruchFont.label).foregroundStyle(Palette.ink)
            }
        }
    }
}

/// Секція «Місця» у видачі пошуку: заклади з тим самим словом. Тап — мапа на закладі.
struct PlacesGroup: View {
    let places: [Place]
    var withCity = false
    let open: (Place) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            GroupLabel(title: Copy.search_places_group)
            GroupedRows {
                ForEach(Array(places.enumerated()), id: \.element.id) { position, place in
                    if position > 0 { Divider().overlay(Palette.hairline).padding(.leading, Space.lg + 40 + Space.md) }
                    PlaceRow(place: place, withCity: withCity) { open(place) }
                }
            }
        }
    }
}

/// Висота картки каруселі, потрібна і самій каруселі.
let mapCardHeight: CGFloat = 112

/// Висота квитка в каруселі мапи з Dynamic Type: росте разом із текстом, до 1.6 раза.
func scaledMapCardHeight(_ scaled: CGFloat) -> CGFloat { min(max(scaled, mapCardHeight), mapCardHeight * 1.6) }

/// Картка каруселі над мапою: досить широка для назви, досить низька, щоб мапу було видно.
struct EventMapCard: View {
    @ScaledMetric(relativeTo: .body) private var cardHeight = mapCardHeight
    let event: Event
    var focused: Bool = false
    var saved: Bool = false
    var onSave: (() -> Void)?
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Ticket(
                stubColor: ticketStub(event), stubLength: 80, radius: Corner.lg, surface: Palette.surfaceRaised,
                outline: focused ? (Palette.ink, StrokeStyle(lineWidth: 2)) : nil
            ) {
                HStack(spacing: Space.md) {
                    EventThumbnail(event: event, maxDimension: 76)
                        .frame(width: 76, height: 76)
                        .clipShape(RoundedRectangle(cornerRadius: Corner.sm, style: .continuous))
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(event.displayTitle).font(PoruchFont.brandTitle3).foregroundStyle(Palette.ink)
                            .multilineTextAlignment(.leading).lineLimit(2)
                        if let badge = eventState(event) { TicketStamp(text: badge.0, tone: badge.1, glyph: badge.2) }
                        // Склад замість місця: на слоті картки місця для обох нема, а хто виступає каже більше.
                        else if let artists = artistsLine(event) { MetaLine(glyph: PoruchIcons.person, text: artists) }
                        else { EventDescriptor(event: event) }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, Space.md).padding(.trailing, Space.sm)
                .frame(height: scaledMapCardHeight(cardHeight))
            } stub: {
                // «Зберегти» на корінці, як на великому квитку: у основній частині назва важливіша.
                VStack(spacing: Space.xs) {
                    if let onSave { SaveButton(saved: saved, action: onSave) }
                    // Жанр словами — в основній частині: на корінці над «Зберегти» й часом йому не лишалось місця.
                    StubTime(event: event, compact: onSave != nil, showsGenre: false)
                }
            }
            .lifted(Elevation.raised)
        }
        .buttonStyle(PressableStyle())
        .ticketAccessibility(event, state: eventState(event)?.0, saved: saved, onSave: onSave)
        .accessibilityAddTraits(focused ? .isSelected : [])
    }
}

/// Що читає VoiceOver на квитку: одне речення в незмінному порядку — назва, жанр, місце, коли, місця, стан.
/// Порядок накладок (штамп, «Зберегти», ціна) на нього не впливає, а жанр звучить словом: колір корінця не озвучується.
func ticketA11yLabel(_ event: Event, state: String? = nil) -> String {
    var parts = [event.displayTitle, hostLine(event) ?? "", categoryName(event.category), eventPlace(event, withCity: false), eventDate(event)]
    if let room = event.gathering, !event.hasEnded(now: nowInstant()) {
        parts.append(Copy.attendees("\(room.attendeeCount)", "\(room.capacity)"))
    }
    if let state { parts.append(state) }
    return parts.filter { !$0.isEmpty }.joined(separator: ", ")
}

extension View {
    /// Квиток для VoiceOver — одна кнопка з `ticketA11yLabel`, а «Зберегти» — дія ротора, а не окрема зупинка між штампом і назвою.
    func ticketAccessibility(_ event: Event, state: String? = nil, saved: Bool = false, onSave: (() -> Void)? = nil) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(ticketA11yLabel(event, state: state))
            .accessibilityAddTraits(.isButton)
            .accessibilityActions {
                if let onSave { Button(saved ? Copy.unsave : Copy.save, action: onSave) }
            }
    }
}

/// «Збирає Тарас» — хто друкує квиток зустрічі. Нема імені (організатор без публічного профілю) — рядка нема.
func hostLine(_ event: Event) -> String? {
    guard let room = event.gathering, !room.organizerName.isEmpty else { return nil }
    return Copy.hosted_by(room.organizerName)
}

/// Рядок «видавця» на квитку зустрічі: аватар і «Збирає Тарас». Від людей — отже, з людиною на квитку.
struct HostLine: View {
    let event: Event
    /// Аватар росте разом із підписом, інакше літера з великим текстом упиралась у коло.
    @ScaledMetric(relativeTo: .footnote) private var avatar: CGFloat = 20
    var body: some View {
        if let line = hostLine(event), let room = event.gathering {
            HStack(spacing: 6) {
                Avatar(name: room.organizerName, url: nil, size: min(avatar, 36))
                Text(line).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary).lineLimit(1)
            }
        }
    }
}

/// Чому квиток тут — тихим рядком: «Для вас», за ким стежите, «Від людей». Штамп лишається лише для стану квитка.
struct ReasonLine: View {
    let text: String
    let glyph: PoruchGlyph
    var body: some View {
        HStack(spacing: Space.xs) {
            PoruchIcon(glyph: glyph, size: 12)
            Text(text).font(PoruchFont.caption).lineLimit(1)
        }
        .foregroundStyle(Palette.inkTertiary)
    }
}

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

// ---- Композиційні картки головної

/// Заклик створити подію: чорна плашка на всю ширину під шапкою головної. Головна одиниця застосунку — зустріч від людини,
/// тож дорога до неї видна одразу, а не лише плюсом у таббарі й рядком унизу. Гостя тап веде до входу.
struct CreateEventCard: View {
    let title: String
    let subtitle: String
    /// Олівець — «друкуєш сам»; інший гліф — та сама порожня форма для іншої першої дії («Знайти подію поруч»).
    var glyph: PoruchGlyph = PoruchIcons.edit
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            // Порожній квиток: свою зустріч друкуєш сам. Корінець чорнильний — це головна дія екрана.
            Ticket(
                stubColor: Palette.brand, stubLength: 64,
                outline: (Palette.inkTertiary.opacity(0.7), StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(PoruchFont.brandTitle3).foregroundStyle(Palette.ink)
                    Text(subtitle).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary)
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, Space.lg).padding(.vertical, Space.md)
                .frame(minHeight: 72, alignment: .leading)
            } stub: {
                // Олівець, а не «+»: плюс уже є на кнопці створення біля таббара, а тут квиток заповнюють.
                PoruchIcon(glyph: glyph, size: 22).foregroundStyle(Palette.onBrand)
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .combine)
    }
}

/// Велика картка-афіша: обкладинка на всю висоту, текст на затемненні внизу. Головний акцент екрана; на головній їх кілька, гортаються.
/// Затемнення низу обкладинки під текстом — одне на велику картку головної й обкладинку деталей, щоб
/// одна й та сама афіша не мінялась тоном між екранами. Кольори на фото від теми не залежать.
let photoScrim = LinearGradient(
    stops: [.init(color: .clear, location: 0.3), .init(color: .black.opacity(0.55), location: 0.7), .init(color: .black.opacity(0.85), location: 1)],
    startPoint: .top, endPoint: .bottom
)

struct EventHeroCard: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let event: Event
    var eyebrow: String?
    var height: CGFloat = 360
    var saved: Bool = false
    var onSave: (() -> Void)?
    let action: () -> Void
    private var place: String { event.placeLabel }
    /// Стан кімнати чи скасування важливіші; інакше штамп каже, чому квиток тут: «Для вас», «Ви стежите».
    /// Штамп — лише стан квитка. Чому квиток тут («Для вас», «Від людей») — тихим рядком під описом.
    private var stamp: (String, BadgeTone, PoruchGlyph?)? { eventState(event) }
    private var reason: (String, PoruchGlyph)? {
        if let eyebrow { return (eyebrow, PoruchIcons.sparkle) }
        return event.gathering == nil ? nil : (Copy.from_people, PoruchIcons.social)
    }
    var body: some View {
        Button(action: action) {
            Ticket(stubColor: ticketStub(event), stubLength: 84, radius: Corner.lg) {
                VStack(alignment: .leading, spacing: 0) {
                    // Розмір картки, а не типовий 800: інакше три hero декодувались у 2400 px і витісняли з кеша постери.
                    // Без фото обкладинки нема: квиток друкований — штамп і назва великим кеглем на самій поверхні.
                    if event.imageUrl != nil {
                        EventArt(event: event, maxDimension: height)
                            .frame(height: height * 0.54).frame(maxWidth: .infinity).clipped()
                            .overlay(alignment: .topLeading) {
                                if let stamp { TicketStamp(text: stamp.0, tone: stamp.1, glyph: stamp.2, onFill: true).padding(Space.md) }
                            }
                    } else if let stamp {
                        TicketStamp(text: stamp.0, tone: stamp.1, glyph: stamp.2).padding([.top, .horizontal], Space.lg)
                    }
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text(event.displayTitle).font(event.imageUrl == nil ? PoruchFont.brandDisplay : PoruchFont.brandTitle1)
                            .foregroundStyle(Palette.ink)
                            .multilineTextAlignment(.leading).lineLimit(event.imageUrl == nil ? 5 : (typeSize.isAccessibilitySize ? 4 : 2))
                            .fixedSize(horizontal: false, vertical: true)
                        HostLine(event: event)
                        EventDescriptor(event: event)
                        if let reason { ReasonLine(text: reason.0, glyph: reason.1) }
                        if let artists = artistsLine(event) { MetaLine(glyph: PoruchIcons.person, text: artists) }
                        if let listing = event.listing {
                            Text(Copy.listing_badge("\(listing.sourceName)")).font(PoruchFont.overline).foregroundStyle(Palette.inkTertiary)
                                .lineLimit(1)
                        }
                    }
                    .padding(Space.lg)
                    Spacer(minLength: 0)
                }
                // Висота — найменша, а не стала: з великим текстом назва, місце й підпис джерела не обрізаються.
                .frame(minHeight: height)
            } stub: {
                VStack(spacing: 0) {
                    if let onSave { SaveButton(saved: saved, action: onSave).padding(.top, Space.md) }
                    Spacer(minLength: 0)
                    StubTime(event: event).padding(.bottom, Space.xl)
                }
            }
        }
        .buttonStyle(PressableStyle())
        .ticketAccessibility(event, state: [stamp?.0, reason?.0].compactMap { $0 }.joined(separator: ", "), saved: saved, onSave: onSave)
    }
}

/// Афіша на всю обкладинку; без фото — насичений градієнт категорії з її великим прозорим гліфом.
/// Одна на hero й постер, щоб подія без фото не блідла серед подій із ним.
struct EventArt: View {
    let event: Event
    /// Найбільша сторона показу в pt: `CachedImage` зменшує зображення ще при розпакуванні.
    var maxDimension: CGFloat = 800
    /// Розмір прозорого гліфа без фото.
    var glyphSize: CGFloat = 220
    /// Наскільки опустити гліф: на деталях верх обкладинки зайнятий смугою статусу й кнопками.
    var glyphDrop: CGFloat = 0
    /// Див. `EventThumbnail.fill`.
    var fill = false
    var body: some View {
        if event.imageUrl == nil {
            ZStack(alignment: .topTrailing) {
                categoryHeroGradient(event.category)
                PoruchIcon(glyph: categoryGlyph(event.category), size: glyphSize)
                    .foregroundStyle(.white.opacity(0.18)).offset(x: glyphSize * 0.25, y: glyphDrop - glyphSize * 0.04)
            }
        } else {
            EventThumbnail(event: event, glyphSize: 72, maxDimension: maxDimension, fill: fill)
        }
    }
}

/// Рядок групового списку: гліф, назва, підпис, справа значення й шеврон. Кілька рядків збирає `GroupedRows`.
struct LinkRow: View {
    let glyph: PoruchGlyph
    let title: String
    var subtitle: String? = nil
    var value: String?
    /// Що нового за рядком («3 нові»): помітніше за [value].
    var badge: String? = nil
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.md) {
                PoruchIcon(glyph: glyph, size: 20).foregroundStyle(Palette.ink)
                    .frame(width: 40, height: 40).background(Palette.surfaceMuted, in: RoundedRectangle(cornerRadius: Corner.xs, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(PoruchFont.cardName).kerning(-0.2).foregroundStyle(Palette.ink).multilineTextAlignment(.leading)
                    if let subtitle {
                        Text(subtitle).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary).multilineTextAlignment(.leading)
                    }
                    // Під підписом, як у списку підписок: праворуч поруч із числом він стискав підпис у три рядки.
                    if let badge { StatusBadge(text: badge, tone: .accent).padding(.top, Space.xs) }
                }
                Spacer(minLength: Space.sm)
                if let value {
                    Text(value).font(PoruchFont.title2).foregroundStyle(Palette.ink).monospacedDigit()
                }
                PoruchIcon(glyph: PoruchIcons.chevronRight, size: 16).foregroundStyle(Palette.inkTertiary)
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
    /// Є нове, але не справа, яку треба рахувати: крапка замість числа.
    var dot = false
    /// Підказка першого знайомства, що вказує на цей пункт.
    var tip: CoachTip?
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
                                        CountBadge(count: item.badge).offset(x: 10, y: -6)
                                    } else if item.dot {
                                        Circle().fill(Palette.accent).frame(width: 8, height: 8).offset(x: 4, y: -2)
                                    }
                                }
                            Text(item.label).font(PoruchFont.overline).lineLimit(1)
                        }
                        .foregroundStyle(selection == item.id ? Palette.ink : Palette.inkTertiary)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background {
                            // Тонова пігулка під активним гліфом: стан видно й на відстані руки. Від кольору
                            // тексту, а не brandContainer: той на склі (≈#F2F2F6) майже зливався з тлом.
                            if selection == item.id { Capsule().fill(Palette.ink.opacity(0.1)) }
                        }
                    }
                    .buttonStyle(PressableStyle(pressedScale: 0.94))
                    .accessibilityLabel(
                        item.badge > 0 ? Copy.a11y_unread_chats("\(item.label)", "\(item.badge)")
                            : item.dot ? Copy.a11y_tab_new_follows("\(item.label)") : item.label
                    )
                    .accessibilityAddTraits(selection == item.id ? .isSelected : [])
                    // Підписи не ростуть вище Large, тож із великим текстом довге натискання показує їх збільшено, як у системному таббарі.
                    .accessibilityShowsLargeContentViewer {
                        PoruchIcon(glyph: item.glyph, size: 22)
                        Text(item.label)
                    }
                    .coachTarget(item.tip)
                }
            }
            // Група вкладок для VoiceOver: «вкладка, 1 з 4», як у системного таббара.
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isTabBar)
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
        .accessibilityLabel(Copy.create)
    }
}
