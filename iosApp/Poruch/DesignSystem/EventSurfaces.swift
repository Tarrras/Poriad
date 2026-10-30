import SwiftUI
import Shared

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

/// Стан події словами: скасовано, відкладено, перенесено, а для кімнати — «ви йдете», запит, черга, місця. Без підпису
/// джерела афіші.
func eventState(_ event: Event, waitlisted: Bool = false) -> (String, BadgeTone, PoruchGlyph?)? {
    if event.isCancelled { return (Copy.cancelled_short, .danger, nil) }
    if let listing = event.listing { return listingStamp(listing) }
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

/// Стан афіші з усіх продавців (docs/event-offers.md R8): відкладено — тривога, як скасування; перенесено — терміновість,
/// подія жива; «не знайшли в продажу» — без тривоги, бо ми не знаємо, що сталось. Скасовану бере `eventState`.
func listingStamp(_ listing: Listing) -> (String, BadgeTone, PoruchGlyph?)? {
    switch listing.state {
    case .postponed: return (Copy.state_postponed, .danger, nil)
    case .unknown: return (Copy.state_unknown, .neutral, nil)
    default: return listing.isMoved ? (Copy.state_moved, .accent, nil) : nil
    }
}

/// Подія від людини, а не з афіші: підпис походження, пара до «Афіша · джерело». Стан кімнати («Ви йдете», «Лишилось 2») важливіший.
func communityBadge(_ event: Event) -> (String, BadgeTone, PoruchGlyph?)? {
    event.gathering == nil ? nil : (Copy.from_people, .neutral, PoruchIcons.social)
}

/// Рядок стану над карткою. Афіша завжди підписана джерелом (docs/event-ingestion.md §8); місця лише в кімнати.
func eventBadge(_ event: Event, waitlisted: Bool = false) -> (String, BadgeTone, PoruchGlyph?)? {
    if let state = eventState(event, waitlisted: waitlisted) { return state }
    guard let listing = event.listing else { return nil }
    return (Copy.listing_badge(listing.sellerNames), .neutral, nil)
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
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        if placeFirst {
            row.accessibilityElement(children: .ignore)
                .accessibilityLabel([categoryName(event.category), place].filter { !$0.isEmpty }.joined(separator: ", "))
        } else {
            row
        }
    }
    private var row: some View {
        // Перенесений заклад (великий шрифт): крапка біля першого рядка, а не між рядками.
        HStack(alignment: typeSize.isAccessibilitySize ? .firstTextBaseline : .center, spacing: Space.sm) {
            CategoryDot(category: event.category)
            if placeFirst {
                // На великому шрифті заклад переноситься: в один рядок від нього лишалось «Будин…».
                Text(place.isEmpty ? categoryName(event.category) : place)
                    .font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary).lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
            } else if typeSize.isAccessibilitySize {
                // Одним текстом, що переноситься: двома в ряд жанр обрізався до «Стен…», а заклад рвався по літерах.
                (Text(categoryName(event.category)).font(PoruchFont.descriptor).foregroundStyle(categoryInk(event.category))
                    + Text(place.isEmpty ? "" : " · " + place).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary))
                    .lineLimit(3)
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
                    if event.hasCover {
                        EventThumbnail(event: event, maxDimension: 420)
                            .frame(height: 180).frame(maxWidth: .infinity).clipped()
                            .overlay(alignment: .topLeading) {
                                if let badge = eventBadge(event, waitlisted: waitlisted) {
                                    TicketStamp(text: badge.0, tone: badge.1, glyph: badge.2, onFill: true).padding(Space.md)
                                }
                            }
                    }
                    VStack(alignment: .leading, spacing: Space.sm) {
                        if !event.hasCover, let badge = eventBadge(event, waitlisted: waitlisted) {
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
                    // Перенесена: стара дата перекреслена, нова — та, що на корінці (питання 6, варіант Б).
                    if let moved = movedLine(event) {
                        moved.font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    EventDescriptor(event: event)
                    if let listing = event.listing, !listing.isWithdrawn {
                        Text(Copy.listing_badge(listing.sellerNames)).font(PoruchFont.overline)
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
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        if let line = hostLine(event), let room = event.gathering {
            HStack(spacing: 6) {
                Avatar(name: room.organizerName, url: nil, size: min(avatar, 36))
                Text(line).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary).lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
            }
        }
    }
}

/// Чому квиток тут — тихим рядком: «Для вас», за ким стежите, «Від людей». Штамп лишається лише для стану квитка.
struct ReasonLine: View {
    let text: String
    let glyph: PoruchGlyph
    /// На accessibility-розмірах причина переноситься: «2 шукають компанію» обрізалось до «2 шу…» (аудит 1.4).
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
            PoruchIcon(glyph: glyph, size: 12)
            Text(text).font(PoruchFont.caption).lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                .fixedSize(horizontal: false, vertical: typeSize.isAccessibilitySize)
        }
        .foregroundStyle(Palette.inkTertiary)
    }
}
