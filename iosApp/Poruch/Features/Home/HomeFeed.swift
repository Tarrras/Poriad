import SwiftUI
import Shared

/// «Від людей»: зустрічі з вільним місцем рейкою квитків (коли їх набралось досить, `HomeRules.people`) і під нею
/// порожній квиток «Організувати подію». Секція є завжди: навіть без зустрічей вона каже, що свою можна зібрати.
/// Гостю під квитком лише тихий рядок входу (без картки): дві картки поспіль товпились би.
struct HomePeopleSection: View {
    let view: HomeScreenState
    /// Деталі події; другий аргумент — звідки тап, для аналітики.
    let open: (String, String) -> Void
    let showPeople: () -> Void
    let createEvent: (String) -> Void
    let openProfile: () -> Void
    @Environment(\.appModel) private var appModel
    private var model: AppModel { appModel! }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader(
                title: Copy.from_people, actionLabel: view.openRooms > 0 ? Copy.home_all_count("\(view.openRooms)") : nil,
                action: view.openRooms > 0 ? showPeople : nil
            ).padding(.horizontal, Space.page)
            if !view.people.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: Space.md) {
                        ForEach(view.people, id: \.event.id) { entry in
                            PosterCard(
                                entry: entry, saved: view.isSaved(entry.event), waitlisted: view.isWaitlisted(entry.event),
                                showsOrigin: false, onSave: { model.app.toggleSaved(id: entry.event.id) }
                            ) { open(entry.event.id, "home_people") }
                            .frame(width: peopleCardWidth).frame(maxHeight: .infinity)
                        }
                    }
                    // Квитки рейки за найвищим: корінці на одній лінії.
                    .fixedSize(horizontal: false, vertical: true)
                }
                .railContentPadding(spread: 0)
                .zIndex(1)
            }
            VStack(alignment: .leading, spacing: Space.xs) {
                CreateEventCard(
                    title: Copy.home_create_title, subtitle: Copy.home_create_subtitle,
                    action: { createEvent("home_top") }
                )
                if !view.signedIn { guestLoginRow }
            }.padding(.horizontal, Space.page)
        }
    }

    /// Рядок входу для гостя: плашка вгорі — єдина головна дія, а вхід — для тих, хто вже має профіль, тож без картки й заливки.
    private var guestLoginRow: some View {
        Button(action: openProfile) {
            HStack(spacing: Space.sm) {
                PoruchIcon(glyph: PoruchIcons.lock, size: 16)
                Text(Copy.guest_home_slim).font(PoruchFont.label)
                Spacer(minLength: Space.sm)
                PoruchIcon(glyph: PoruchIcons.chevronRight, size: 15)
            }
            .foregroundStyle(Palette.inkSecondary)
            .padding(.horizontal, Space.xs).frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(pressedScale: 1))
        .accessibilityLabel(Copy.guest_home_slim)
    }
}

/// «У місті»: три великі картки, що гортаються (сусідня визирає), чипи, далі сітка постерів у дві колонки.
struct HomeCityFeed: View {
    let view: HomeScreenState
    /// Скільки рядків показано (`HomeView.feedLimit`): чип скидає, «Показати ще» додає.
    @Binding var feedLimit: Int
    /// Деталі події; другий аргумент — звідки тап, для аналітики.
    let open: (String, String) -> Void
    /// «Усі N»: мапа з усім містом.
    let showCity: () -> Void
    let openMap: () -> Void
    @Environment(\.appModel) private var appModel
    private var model: AppModel { appModel! }

    var body: some View {
        if !view.feed.isEmpty {
            let picks = Array(view.feed.prefix(homeHeroCount))
            // Сітку вже звузив презентер обраним чипом (`view.feedFilter`).
            let shown = Array(view.feed.dropFirst(homeHeroCount))
            VStack(alignment: .leading, spacing: Space.md) {
                if view.offline { OfflineNote().padding(.horizontal, Space.page) }
                SectionHeader(
                    title: Copy.home_in_city, actionLabel: view.totalFound > 0 ? Copy.home_all_count("\(view.totalFound)") : nil,
                    action: view.totalFound > 0 ? showCity : nil
                ).padding(.horizontal, Space.page)
                heroPager(picks)
                if !view.chips.isEmpty { feedChips(view.chips, selected: view.feedFilter) }
                if !shown.isEmpty {
                    // Ряди по два квитки однакової висоти: корінці в ряду стоять на одній лінії, хоч би скільки рядків мав підпис.
                    let visible = Array(shown.prefix(feedLimit))
                    LazyVStack(spacing: Space.xl) {
                        ForEach(Array(stride(from: 0, to: visible.count, by: 2)), id: \.self) { index in
                            HStack(alignment: .top, spacing: Space.md) {
                                cityPoster(visible[index])
                                if index + 1 < visible.count { cityPoster(visible[index + 1]) } else { Color.clear }
                            }
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, Space.page).padding(.top, Space.md)
                    if shown.count > feedLimit {
                        SecondaryButton(title: Copy.show_more) { feedLimit += Int(HomeRules.shared.FEED_PAGE) }
                            .padding(.horizontal, Space.page)
                    }
                }
            }
        } else if view.isEmpty {
            if view.loading {
                PoruchLoader().frame(maxWidth: .infinity).padding(.vertical, Space.section)
            } else if view.offline {
                // Без мережі «тихо» було б неправдою: афіша є, її не видно. Відкриється сама, щойно мережа повернеться.
                EmptyState(glyph: PoruchIcons.wifiOff, title: Copy.offline_title, message: Copy.offline_home_hint, animation: "Offline")
            } else {
                EmptyState(
                    glyph: PoruchIcons.compass, title: Copy.nothing_here,
                    message: Copy.nothing_here_hint,
                    actionLabel: Copy.find_on_map, action: openMap
                )
            }
        }
    }

    private func cityPoster(_ entry: FeedEntry) -> some View {
        PosterCard(
            entry: entry, saved: view.isSaved(entry.event), waitlisted: view.isWaitlisted(entry.event),
            onSave: { model.app.toggleSaved(id: entry.event.id) }
        ) {
            open(entry.event.id, "home_poster")
        }
        .frame(maxHeight: .infinity)
    }

    /// Ряд чипів над сіткою: час, безкоштовне й найбільші категорії. Звужує лише сітку, великі картки стоять.
    private func feedChips(_ chips: [FeedFilter], selected: FeedFilter) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.sm) {
                ForEach(chips, id: \.self) { chip in
                    Chip(label: feedChipLabel(chip), dot: chip.category, selected: chip == selected) {
                        withMotion { model.homeScreen.selectFeedFilter(chip) }
                        feedLimit = Int(HomeRules.shared.FEED_PAGE)
                    }
                }
            }
        }.railContentPadding(spread: 0)
    }

    /// Гортана стрічка великих карток: наступна визирає з-за краю, як у Moonly.
    private func heroPager(_ picks: [FeedEntry]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.md) {
                ForEach(picks, id: \.event.id) { entry in
                    EventHeroCard(
                        event: entry.event, eyebrow: lane(entry),
                        saved: view.isSaved(entry.event), onSave: { model.app.toggleSaved(id: entry.event.id) }
                    ) { open(entry.event.id, "home_hero") }
                    .containerRelativeFrame(.horizontal) { width, _ in picks.count > 1 ? width * 0.86 : width - 2 * Space.page }
                    .frame(maxHeight: .infinity)
                }
            }
            // Великі квитки за найвищим: з великим текстом корінці стоять на одній лінії.
            .fixedSize(horizontal: false, vertical: true)
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .railContentPadding(spread: 0)
        .zIndex(1)
    }
}

/// Без фільтра: усе, що є в сітці.

private func feedChipLabel(_ chip: FeedFilter) -> String {
    switch chip.kind {
    case .today: Copy.today
    case .tomorrow: Copy.tomorrow
    case .weekend: Copy.weekend
    case .free: Copy.listing_free
    case .category: chip.category.map(categoryName) ?? Copy.feed_all
    default: Copy.feed_all
    }
}

/// Підпис джерела в стрічці: «Для вас», «Ви стежите · МУР». Афіша міста без підпису.
private func lane(_ entry: FeedEntry) -> String? {
    switch entry.source {
    case .forYou: Copy.picked_for_you
    case .following: entry.followName.map { Copy.follow_via($0) } ?? Copy.following
    default: nil
    }
}

/// Ширина постера в рейці «Від людей»: як в одній колонці сітки, щоб третій визирав із-за краю.
private let peopleCardWidth: CGFloat = 176

/// Вертикальний квиток у сітці «У місті» й рейці «Від людей»: обкладинка 4:5 і назва вгорі, а за перфорацією корінець
/// кольору жанру з годиною, днем і, для зустрічі, місцями «3/8». Ціна — плашкою на фото, стан кімнати («Ви йдете»,
/// «Лишилось 2») — штампом нагорі замість підпису «Для вас».
private struct PosterCard: View {
    let entry: FeedEntry
    let saved: Bool
    let waitlisted: Bool
    /// Підпис «Від людей» на кімнаті без стану: у секції «Від людей» він зайвий.
    var showsOrigin = true
    let onSave: () -> Void
    let open: () -> Void

    private var event: Event { entry.event }

    /// «Від 390 ₴» лише коли джерело сказало ціну. Місця зустрічі — на корінці.
    private var price: String? {
        guard event.gathering == nil, let listing = event.listing,
              listing.isFree?.boolValue == true || listing.priceMin != nil else { return nil }
        return listingPrice(listing)
    }

    /// Стан: скасоване — штампом (корінець тоді погашений), для кімнати — «Ви йдете», «Лишилось 2». Знята афіша сказана підписом.
    private var state: (String, BadgeTone, PoruchGlyph?)? {
        if event.isCancelled { return (Copy.cancelled_short, .danger, nil) }
        return event.gathering == nil ? nil : eventState(event, waitlisted: waitlisted)
    }

    /// Афіша завжди підписана джерелом (docs/event-ingestion.md §8).
    private var note: (String, Color)? {
        guard let listing = event.listing else { return nil }
        if listing.isWithdrawn, let stamp = listingStamp(listing) { return (stamp.0, Palette.inkTertiary) }
        return (Copy.listing_badge(listing.sellerNames), Palette.inkTertiary)
    }

    @Environment(\.dynamicTypeSize) private var typeSize

    /// Друкована сторона без фото дає назві чотири рядки; з великим текстом — на рядок більше, щоб назва не тонула в «…».
    private var titleLines: Int { (event.imageUrl == nil ? 4 : 2) + (typeSize.isAccessibilitySize ? 1 : 0) }

    /// Штамп — лише стан квитка: скасовано, «Ви йдете», «Лишилось 2». Чому квиток тут — [reason], тихим рядком.
    @ViewBuilder private func stampView(onFill: Bool) -> some View {
        if let state { TicketStamp(text: state.0, tone: state.1, glyph: state.2, onFill: onFill) }
    }

    /// Чому квиток у стрічці: за ким стежите (дзвіночок і ім'я), «Для вас», «Від людей». Не штамп, бо нічого з
    /// квитком не сталось — штамп поруч зі «Скасовано» й «Лишилось 2» мав би однакову вагу.
    private var reason: (String, PoruchGlyph)? {
        if entry.source == .following { return (entry.followName ?? Copy.following, PoruchIcons.bell) }
        if let label = lane(entry) { return (label, PoruchIcons.sparkle) }
        if showsOrigin, event.gathering != nil { return (Copy.from_people, PoruchIcons.social) }
        return nil
    }

    var body: some View {
        Button(action: open) {
            // 64: жанр над часом — два рядки, і в 52 вони впирались у перфорацію та нижній край.
            Ticket(vertical: true, stubColor: ticketStub(event), stubLength: 64) {
                VStack(alignment: .leading, spacing: 0) {
                    if event.imageUrl != nil {
                        // Пріоритет: у ряду однакової висоти фото бере свої 4:5 першим, а запас іде полю під назвою.
                        Color.clear.aspectRatio(4.0 / 5.0, contentMode: .fit)
                            .overlay { EventArt(event: event, maxDimension: 420) }
                            .clipped()
                            .layoutPriority(1)
                            .overlay(alignment: .topLeading) {
                                // Поле праворуч — під «Зберегти»: довгий штамп стискається, а не лягає на кнопку.
                                stampView(onFill: true).padding(Space.sm).padding(.trailing, 40)
                            }
                            .overlay(alignment: .topTrailing) { SaveButton(saved: saved, action: onSave).padding(Space.xs) }
                            .overlay(alignment: .bottomLeading) {
                                if let price { StatusBadge(text: price, onPhoto: true).padding(Space.sm) }
                            }
                    } else {
                        // Без фото — друкована сторона квитка: штамп і «Зберегти» вгорі, назва великим кеглем.
                        HStack(alignment: .top) {
                            stampView(onFill: false).padding(.top, Space.xs)
                            Spacer(minLength: Space.xs)
                            SaveButton(saved: saved, action: onSave)
                        }
                        .padding([.top, .horizontal], Space.sm)
                    }
                    // Як на друкованому квитку: місце й підписи притиснуті до перфорації, вільне поле лишається під назвою.
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(event.displayTitle)
                            .font(event.imageUrl == nil ? PoruchFont.brandTitle2 : PoruchFont.brandTitle3).foregroundStyle(Palette.ink)
                            .multilineTextAlignment(.leading)
                            .lineLimit(titleLines)
                        HostLine(event: event)
                        Spacer(minLength: Space.sm)
                        if let reason { ReasonLine(text: reason.0, glyph: reason.1) }
                        EventDescriptor(event: event, placeFirst: true)
                        if event.imageUrl == nil, let price {
                            Text(price).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary).lineLimit(1)
                        }
                        if let series = seriesNote(event) {
                            Text(series).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary).lineLimit(1)
                        }
                        if let note { Text(note.0).font(PoruchFont.overline).foregroundStyle(note.1).lineLimit(1) }
                    }
                    .padding(.horizontal, Space.md).padding(.top, Space.md).padding(.bottom, Space.lg)
                    .frame(maxHeight: .infinity, alignment: .top)
                }
            } stub: {
                StubTime(event: event, row: true)
            }
        }
        .buttonStyle(PressableStyle())
        .ticketAccessibility(event, state: [state?.0, reason?.0, price, note?.0].compactMap { $0 }.joined(separator: ", "), saved: saved, onSave: onSave)
    }
}
