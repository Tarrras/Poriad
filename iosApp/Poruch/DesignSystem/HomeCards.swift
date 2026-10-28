import SwiftUI
import Shared

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
                        // Афіша підписана джерелом скрізь, і в стосі «Ваш тиждень» теж: так обіцяють Умови, розділ 7.
                        if let listing = event.listing {
                            Text(Copy.listing_badge(listing.sellerNames)).font(PoruchFont.overline).foregroundStyle(Palette.inkTertiary)
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
            // На великому шрифті підпис стискається, а не обрізається посеред слова.
            Text(title).font(PoruchFont.label).foregroundStyle(enabled ? Palette.ink : Palette.inkTertiary).lineLimit(1).minimumScaleFactor(0.75)
        }.frame(maxWidth: .infinity)
    }
}
