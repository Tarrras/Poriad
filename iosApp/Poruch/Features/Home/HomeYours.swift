import SwiftUI
import Shared

/// «Ваше»: усе особисте одним блоком у [HomeRules.YOURS_ROWS] рядки — найближчий план карткою з діями, решта планів,
/// «Ваш тиждень», дати артистів у місті й «Ви стежите». Кожен новий гачок дістає рядок тут, а не секцію над афішею.
/// Гостю — те, що в нього є без входу: стос і артисти на телефоні. Порожньо — блоку нема: створити подію пропонує рейка вище.
struct HomePersonalSection: View {
    let view: HomeScreenState
    /// «Ваш тиждень» цього тижня ще не відкривали (тиждень відкриття — на телефоні).
    let deckDue: Bool
    /// Деталі події; другий аргумент — звідки тап, для аналітики.
    let open: (String, String) -> Void
    let openChat: (Event) -> Void
    let openMyEvents: () -> Void
    let openFollows: () -> Void
    let openDeck: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let slots = view.yours(deckDue: deckDue)
        if !slots.isEmpty { block(slots) }
    }

    private func block(_ slots: YoursSlots) -> some View {
        // Велика картка — першому плану, що скоро чи чекає на людину; минула чи далека подія лишається рядком.
        let now = nowInstant()
        let zone = TimeZone.current.identifier
        let personal = Array(view.personal.prefix(Int(slots.plans)))
        let leadIndex = personal.firstIndex {
            HomeRules.shared.isLead(event: $0.event, waiting: $0.chat != nil || $0.requests > 0, now: now, zoneId: zone)
        }
        let lead = leadIndex.map { personal[$0] }
        let rows = personal.enumerated().filter { $0.offset != leadIndex }.map(\.element)
        var items: [AnyView] = []
        items += rows.map { row in AnyView(PlanRow(row: row, open: { open(row.event.id, "home_your") }, chat: { openChat(row.event) }).morphSource("home_your/\(row.event.id)")) }
        if slots.waiting { items.append(AnyView(waitingRow(Int(view.moreWaiting)))) }
        if slots.deck { items.append(AnyView(deckRow)) }
        items += view.radarDates.prefix(Int(slots.dates)).map { AnyView(dateRow($0)) }
        if slots.follows { items.append(AnyView(followsRow(view.followLine(shownDates: slots.dates)))) }
        let grouped = items
        return VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader(
                title: Copy.home_yours, actionLabel: view.personal.isEmpty ? nil : Copy.my_events,
                action: view.personal.isEmpty ? nil : openMyEvents
            )
            if let lead {
                // Свій стан на кожен план: штамп падає раз, коли найближчим став інший план.
                NextPlanCard(row: lead, open: { open(lead.event.id, "home_your") }, chat: { openChat(lead.event) })
                    .id(lead.event.id)
                    .morphSource("home_your/\(lead.event.id)")
            }
            if !grouped.isEmpty {
                GroupedRows {
                    ForEach(grouped.indices, id: \.self) { position in
                        if position > 0 { yourDivider }
                        grouped[position]
                    }
                }
            }
        }.padding(.horizontal, Space.page)
    }

    private var yourDivider: some View {
        // На великому шрифті текст рядка під плиткою, від краю: волосина теж.
        Divider().overlay(Palette.hairline).padding(.leading, typeSize.isAccessibilitySize ? Space.lg : Space.lg + yourTile + Space.md)
    }

    private var chevron: some View {
        PoruchIcon(glyph: PoruchIcons.chevronRight, size: 16).foregroundStyle(Palette.inkTertiary)
    }

    /// «Ваш тиждень» (docs/return-hooks.md): раз на тиждень, поки стос цього тижня не відкривали.
    private var deckRow: some View {
        YourRow(overline: nil, title: Copy.deck_title, subtitle: Copy.deck_row_subtitle, open: openDeck) {
            YourGlyphTile(glyph: PoruchIcons.sparkle)
        } trailing: { chevron }
    }

    /// Вечір «Ваших артистів» у місті (docs/artist-radar.md): дата, назва події, хто з артистів — усі, а не рядок на кожного.
    private func dateRow(_ date: RadarDate) -> some View {
        let day = parseEventDate(date.event.startsAt).map {
            formatter(zone: date.event.timeZone, "EE d.MM").string(from: $0).uppercased(with: Locale(identifier: "uk_UA"))
        }
        return YourRow(
            overline: day, title: date.event.displayTitle, subtitle: date.artists.joined(separator: ", "),
            open: { open(date.event.eventId, "radar") }, brandTitle: true
        ) {
            categoryTile(date.event.category)
        } trailing: { chevron }
        .morphSource("radar/\(date.event.eventId)")
    }

    /// Плитка дати — кольору й гліфа жанру, як корінець квитка: три дати поспіль не зливаються в однакові рядки.
    private func categoryTile(_ category: EventCategory) -> some View {
        ZStack {
            categoryGradient(category)
            PoruchIcon(glyph: categoryGlyph(category), size: 24).foregroundStyle(categoryInk(category))
        }
        .frame(width: yourTile, height: yourTile)
        .clipShape(RoundedRectangle(cornerRadius: Corner.sm, style: .continuous))
    }

    /// «Ви стежите» і за ким — двома першими іменами, як і веде тап: на екран «Ви стежите». Спершу артисти дат, що не
    /// влізли вище, далі заклади й організатори. Імен нема (список не доїхав) — назва події.
    private func followsRow(_ names: [String]) -> some View {
        // Лише артисти дат, що не влізли: одне ім'я й «та ще 5 артистів» — число не читається подіями й влазить у рядок.
        let artistsOnly = view.followNames.isEmpty
        let lead = artistsOnly ? 1 : 2
        let shown = names.isEmpty ? (view.followed.first?.displayTitle ?? "") : names.prefix(lead).joined(separator: ", ")
        let more = names.count - lead
        let subtitle = more <= 0 ? shown
            : artistsOnly ? shown + " " + Copy.home_follows_more_artists(more) : Copy.home_follows_more(shown, "\(more)")
        return YourRow(
            overline: nil, title: Copy.follows_title, subtitle: subtitle, open: openFollows
        ) {
            YourGlyphTile(glyph: PoruchIcons.bellActive)
        } trailing: {
            // Нове ще не переглянуте — бейдж замість шеврона: рядок тепер про те, що чекає.
            if view.newFollowEvents > 0 {
                StatusBadge(text: Copy.follows_new(Int(view.newFollowEvents)), tone: .accent)
            } else {
                chevron
            }
        }
    }

    /// Ті, що чекають відповіді, але в «Ваше» не влізли: їх видно лише в «Моїх подіях».
    private func waitingRow(_ count: Int) -> some View {
        YourRow(
            overline: nil, title: Copy.home_waiting_more("\(count)"), subtitle: Copy.home_waiting_more_hint, open: openMyEvents
        ) {
            YourGlyphTile(glyph: PoruchIcons.chat)
        } trailing: { chevron }
    }
}

/// Гліф у плитці службового рядка «Ваше»: тиждень, артисти, підписки, «чекають ще».
private struct YourGlyphTile: View {
    let glyph: PoruchGlyph
    var body: some View {
        PoruchIcon(glyph: glyph, size: 20).foregroundStyle(Palette.ink)
            .frame(width: yourTile, height: yourTile)
            .background(Palette.surfaceMuted, in: RoundedRectangle(cornerRadius: Corner.sm, style: .continuous))
    }
}

/// Обкладинка-плитка блоку «Ваше».
private let yourTile: CGFloat = 52

/// Рядок блоку «Ваше»: плитка, надрядок, назва, підпис. `trailing` лежить у тапі рядка, а лічильник чату — окремою кнопкою.
private struct YourRow<Tile: View, Trailing: View>: View {
    let overline: String?
    let title: String
    let subtitle: String?
    let open: () -> Void
    /// Непрочитане: кнопка праворуч, що веде просто в чат. Тоді `trailing` не малюється.
    var chat: (count: Int, open: () -> Void)?
    /// Назва події (а не службового рядка) — кондензом, як у постері.
    var brandTitle = false
    @ViewBuilder let tile: Tile
    @ViewBuilder let trailing: Trailing
    /// На accessibility-розмірах надрядок і підпис переносяться до трьох рядків: в один від «Арсен Пучков» лишалось
    /// «Арсен Пу…», а рядок радару для того й існує, щоб сказати, хто грає (аудит 1.4). Плитка й стан стають рядком
    /// над текстом: поруч вони стискали назву до «Музика всесв…».
    @Environment(\.dynamicTypeSize) private var typeSize
    private var metaLines: Int { typeSize.isAccessibilitySize ? 3 : 1 }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let overline {
                Text(overline).font(PoruchFont.overline).kerning(1.0).foregroundStyle(Palette.inkTertiary).lineLimit(metaLines)
            }
            Text(title).font(brandTitle ? PoruchFont.brandTitle3 : PoruchFont.cardName).kerning(brandTitle ? -0.1 : -0.2)
                .foregroundStyle(Palette.ink).multilineTextAlignment(.leading).lineLimit(typeSize.isAccessibilitySize ? 4 : 2)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary).lineLimit(metaLines)
            }
        }
    }

    var body: some View {
        HStack(spacing: Space.sm) {
            Button(action: open) {
                Group {
                    if typeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            HStack(spacing: Space.md) { tile; Spacer(minLength: 0); if chat == nil { trailing } }
                            texts
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        HStack(spacing: Space.md) {
                            tile
                            texts
                            Spacer(minLength: 0)
                            if chat == nil { trailing }
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(pressedScale: 1))
            .accessibilityElement(children: .combine)
            if let chat {
                Button(action: chat.open) {
                    CountBadge(count: chat.count).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(Copy.home_chat_a11y("\(chat.count)"))
            }
        }
        .padding(.horizontal, Space.lg).padding(.vertical, Space.md)
    }
}

/// Кнопка-пігулка картки плану. Підсвічена (чорнилом), коли за нею є що робити: нове в чаті, запити.
private struct PlanButton: View {
    let title: String
    let glyph: PoruchGlyph
    var highlight = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.xs) {
                PoruchIcon(glyph: glyph, size: 17)
                Text(title).font(PoruchFont.label).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(highlight ? Palette.onBrand : Palette.ink)
            .frame(maxWidth: .infinity).frame(minHeight: 44).padding(.vertical, 2)
            .background(highlight ? Palette.brand : Palette.brandContainer, in: buttonShape)
        }
        .buttonStyle(PressableStyle())
    }
}

/// «Ваш наступний квиток» (вау головної, docs/design-wow-1.5.md): найближчий план — квитком «Корінця» з корінцем часу й
/// дня кольору жанру, на ньому штамп ролі, як на деталях після запису. Під квитком дії — маршрут, чат, запити.
private struct NextPlanCard: View {
    let row: PersonalRow
    let open: () -> Void
    let chat: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.homeCovered) private var covered
    /// Системне питання (геолокація, сповіщення) робить застосунок неактивним: удар під ним не видно.
    @Environment(\.scenePhase) private var phase
    @ScaledMetric(relativeTo: .body) private var ticketHeight: CGFloat = 132
    /// Штамп ще не впав: план новий для головної. Рух — раз на план, а не на кожне відкриття, інакше він читався б затримкою.
    @State private var armed: Bool
    @State private var hit = 0
    /// Квиток над таббаром: удар, якого не видно, пішов би в порожнечу, а план уже вважався б показаним.
    @State private var onScreen = false

    init(row: PersonalRow, open: @escaping () -> Void, chat: @escaping () -> Void) {
        self.row = row
        self.open = open
        self.chat = chat
        // «Зменшити рух» — штамп одразу на місці, без удару.
        _armed = State(initialValue: !PlanStamps.shown(row.event.id) && !UIAccessibility.isReduceMotionEnabled)
    }

    private var event: Event { row.event }

    private var today: Bool { parseEventDate(event.startsAt).map(Calendar.current.isDateInToday) == true }

    /// На великому шрифті квиток вертикальний, корінець знизу: праворуч він стискав назву до складів.
    private var upright: Bool { typeSize.isAccessibilitySize }

    /// Остання репліка чату, коли є нове; інакше місце.
    private var subtitle: String {
        if let unread = row.chat, !unread.lastBody.isEmpty {
            let author = unread.lastAuthorName.isEmpty ? Copy.chat_member : unread.lastAuthorName
            return "\(author): «\(unread.lastBody.replacingOccurrences(of: "\n", with: " "))»"
        }
        return event.placeLabel
    }

    /// Роль штампом, як на деталях: «Ваша подія», «Ви йдете»; запити, що чекають, важливіші. Скасованої тут не буває:
    /// `HomeRules.isLead` її не пропускає.
    private var stamp: TicketStamp {
        if row.requests > 0 { return TicketStamp(text: Copy.home_requests_short("\(row.requests)"), tone: .accent, glyph: PoruchIcons.personAdd) }
        return row.organizing
            ? TicketStamp(text: Copy.home_role_organizer, tone: .brand)
            : TicketStamp(text: Copy.going, tone: .success, glyph: PoruchIcons.check)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Button(action: open) {
                Ticket(vertical: upright, stubColor: ticketStub(event), stubLength: upright ? 64 : 80, radius: Corner.lg, surface: Palette.surfaceRaised) {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        HStack(alignment: .top, spacing: Space.sm) {
                            // Відлік лише сьогодні: «через 25 год» про завтрашнє нічого не каже, а день — на корінці.
                            if today {
                                Text(countdownOverline(event)).font(PoruchFont.overline).kerning(1.0).foregroundStyle(Palette.accentText)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            StampDrop(stamp: stamp, hit: hit, armed: armed)
                        }
                        Text(event.cardTitle).font(PoruchFont.brandTitle2).kerning(-0.2).foregroundStyle(Palette.ink)
                            .multilineTextAlignment(.leading).lineLimit(upright ? nil : 2)
                        Text(subtitle).font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary)
                            .multilineTextAlignment(.leading).lineLimit(upright ? 3 : (row.chat == nil ? 1 : 2))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Space.lg).padding(.vertical, Space.md)
                    .frame(maxWidth: .infinity, minHeight: upright ? nil : ticketHeight, alignment: .topLeading)
                } stub: {
                    StubTime(event: event, row: upright)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(pressedScale: 1))
            .accessibilityElement(children: .ignore)
            // Квиток — одне речення; відлік і нове в чаті — те, що на ньому видно понад звичайний квиток.
            .accessibilityLabel(
                [ticketA11yLabel(event, state: stamp.text), today ? countdownOverline(event) : nil, row.chat != nil ? subtitle : nil]
                    .compactMap { $0 }.joined(separator: ", ")
            )
            .accessibilityAddTraits(.isButton)
            // Видно — коли центр квитка над таббаром: цілком на SE він часто не вміщається під «З ким піти».
            .onGeometryChange(for: Bool.self) { proxy in
                let frame = proxy.frame(in: .scrollView)
                let height = proxy.bounds(of: .scrollView)?.height ?? .infinity
                return frame.midY > 0 && frame.midY < height - tabBarClearance
            } action: { onScreen = $0 }
            // Великий шрифт: дії одна під одною, як у «Моїх подіях», — три в ряд обрізали б «Маршрут» до «Ма…».
            let actions = upright ? AnyLayout(VStackLayout(spacing: Space.sm)) : AnyLayout(HStackLayout(spacing: Space.sm))
            actions {
                // Маршрут — головна дія, поки подія сьогодні й ще не почалась; далі — звичайна.
                PlanButton(
                    title: Copy.open_in_maps, glyph: PoruchIcons.directions,
                    highlight: today && !event.hasStarted(now: nowInstant())
                ) { SystemActions.openInMaps(event) }
                PlanButton(
                    title: row.chat.map { Copy.chat_short_unread("\($0.unread)") } ?? Copy.chat_short, glyph: PoruchIcons.chat,
                    highlight: row.chat != nil, action: chat
                )
                if row.requests > 0 {
                    PlanButton(title: Copy.home_requests_short("\(row.requests)"), glyph: PoruchIcons.personAdd, highlight: true, action: open)
                }
            }
        }
        // Стрічка не лінива: `.task` спрацював би на вставці, поза екраном. Удар — коли квиток видно, а головну нічим не
        // закрито; зникло посеред паузи — завдання скасовується, і план лишається новим.
        .task(id: onScreen && !covered && phase == .active) {
            guard onScreen, !covered, phase == .active, !PlanStamps.shown(event.id) else { return }
            // Хай головна спершу ляже: удар у першому ж кадрі губився б у появі стрічки.
            if armed { guard (try? await Task.sleep(for: .milliseconds(350))) != nil else { return } }
            PlanStamps.remember(event.id)
            if armed { armed = false; hit += 1 }
        }
    }
}

extension EnvironmentValues {
    /// Головну закриває інший екран чи лист (`RootView`): рух на ній ніхто не побачить.
    @Entry var homeCovered = false
}

/// Таббар плаває над низом стрічки: квиток під ним не видно.
private let tabBarClearance: CGFloat = 92

/// Плани, на які штамп уже падав: A → B → A — без другого удару. Останні 20, щоб список не ріс.
private enum PlanStamps {
    private static let key = "poruch.home.shownPlans"
    static func shown(_ id: String) -> Bool { (UserDefaults.standard.stringArray(forKey: key) ?? []).contains(id) }
    static func remember(_ id: String) {
        let ids = (UserDefaults.standard.stringArray(forKey: key) ?? []).filter { $0 != id } + [id]
        UserDefaults.standard.set(Array(ids.suffix(20)), forKey: key)
    }
}

/// Своя подія: категорія плиткою, час, назва, роль першим словом підпису («Ваша подія · Будинок Актора»). Праворуч — лише
/// лічильник чату чи шеврон: бейдж ролі з'їдав ~110 pt і рвав назву на SE.
private struct PlanRow: View {
    let row: PersonalRow
    let open: () -> Void
    let chat: () -> Void

    private var event: Event { row.event }

    /// Моя роль у події; скасована чи минула — ролі вже нема.
    private var role: String? {
        if event.isCancelled || event.hasEnded(now: nowInstant()) { return nil }
        return row.organizing ? Copy.home_role_organizer : Copy.going
    }

    /// Роль першим словом, далі те, що чекає: запити, нове в чаті, інакше місце.
    private var subtitle: String? {
        let detail: String
        if row.requests > 0 {
            detail = Copy.requests_count(Int(row.requests))
        } else if let chat = row.chat {
            let author = chat.lastAuthorName.isEmpty ? Copy.chat_member : chat.lastAuthorName
            let body = chat.lastBody.replacingOccurrences(of: "\n", with: " ")
            detail = body.isEmpty ? Copy.new_messages_count("\(chat.unread)") : "\(author): «\(body)»"
        } else {
            detail = event.placeLabel
        }
        return [role, detail].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Лічильник — кнопка в чат, поки праворуч не зайняли запити: на них теж чекає людина, і вони важливіші.
    private var chatButton: (count: Int, open: () -> Void)? {
        guard let unread = row.chat, row.requests == 0 else { return nil }
        return (Int(unread.unread), chat)
    }

    var body: some View {
        YourRow(overline: cardOverline(event), title: event.cardTitle, subtitle: subtitle, open: open, chat: chatButton, brandTitle: true) {
            EventThumbnail(event: event, glyphSize: 24, maxDimension: 52)
                .frame(width: yourTile, height: yourTile)
                .clipShape(RoundedRectangle(cornerRadius: Corner.sm, style: .continuous))
        } trailing: {
            // Скасовану гасить штамп, як скрізь; решта — шеврон.
            if event.isCancelled {
                TicketStamp(text: Copy.cancelled_short, tone: .danger)
            } else {
                PoruchIcon(glyph: PoruchIcons.chevronRight, size: 16).foregroundStyle(Palette.inkTertiary)
            }
        }
    }
}
