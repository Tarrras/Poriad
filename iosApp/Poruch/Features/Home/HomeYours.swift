import SwiftUI
import Shared

/// «Ваше»: найближчий план карткою з діями, решта планів і підписки — рядками під нею. Гостю блоку нема, як і людині без
/// планів і підписок: створити подію їй пропонує плашка вгорі, а порожній рядок «Планів нема» лише дублював би її.
struct HomePersonalSection: View {
    let view: HomeScreenState
    /// Деталі події; другий аргумент — звідки тап, для аналітики.
    let open: (String, String) -> Void
    let openChat: (Event) -> Void
    let openMyEvents: () -> Void
    let openFollows: () -> Void

    var body: some View {
        if !view.personal.isEmpty || !view.followed.isEmpty { block }
    }

    private var block: some View {
        // Велика картка — першому плану, що скоро чи чекає на людину; минула чи далека подія лишається рядком.
        let now = nowInstant()
        let zone = TimeZone.current.identifier
        let leadIndex = view.personal.firstIndex {
            HomeRules.shared.isLead(event: $0.event, waiting: $0.chat != nil || $0.requests > 0, now: now, zoneId: zone)
        }
        let lead = leadIndex.map { view.personal[$0] }
        let rows = view.personal.enumerated().filter { $0.offset != leadIndex }.map(\.element)
        var items: [AnyView] = []
        items += rows.map { row in AnyView(PlanRow(row: row, open: { open(row.event.id, "home_your") }, chat: { openChat(row.event) })) }
        if view.moreWaiting > 0 { items.append(AnyView(waitingRow(Int(view.moreWaiting)))) }
        if !view.followed.isEmpty { items.append(AnyView(followsRow)) }
        let grouped = items
        return VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader(
                title: Copy.home_yours, actionLabel: view.personal.isEmpty ? nil : Copy.my_events,
                action: view.personal.isEmpty ? nil : openMyEvents
            )
            if let lead {
                NextPlanCard(row: lead, open: { open(lead.event.id, "home_your") }, chat: { openChat(lead.event) })
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
        Divider().overlay(Palette.hairline).padding(.leading, Space.lg + yourTile + Space.md)
    }

    /// «Ви стежите» і за ким — двома першими іменами, як і веде тап: на екран «Ви стежите». Імен нема (список не доїхав) — назва події.
    private var followsRow: some View {
        let names = view.followNames
        let shown = names.isEmpty ? (view.followed.first?.displayTitle ?? "") : names.prefix(2).joined(separator: ", ")
        return YourRow(
            overline: nil, title: Copy.follows_title,
            subtitle: names.count > 2 ? Copy.home_follows_more(shown, "\(names.count - 2)") : shown, open: openFollows
        ) {
            PoruchIcon(glyph: PoruchIcons.bellActive, size: 20).foregroundStyle(Palette.ink)
                .frame(width: yourTile, height: yourTile)
                .background(Palette.surfaceMuted, in: RoundedRectangle(cornerRadius: Corner.sm, style: .continuous))
        } trailing: {
            // Нове ще не переглянуте — бейдж замість шеврона: рядок тепер про те, що чекає.
            if view.newFollowEvents > 0 {
                StatusBadge(text: Copy.follows_new(Int(view.newFollowEvents)), tone: .accent)
            } else {
                PoruchIcon(glyph: PoruchIcons.chevronRight, size: 16).foregroundStyle(Palette.inkTertiary)
            }
        }
    }

    /// Ті, що чекають відповіді, але в «Ваше» не влізли: їх видно лише в «Моїх подіях».
    private func waitingRow(_ count: Int) -> some View {
        YourRow(
            overline: nil, title: Copy.home_waiting_more("\(count)"), subtitle: Copy.home_waiting_more_hint, open: openMyEvents
        ) {
            PoruchIcon(glyph: PoruchIcons.chat, size: 20).foregroundStyle(Palette.ink)
                .frame(width: yourTile, height: yourTile)
                .background(Palette.surfaceMuted, in: RoundedRectangle(cornerRadius: Corner.sm, style: .continuous))
        } trailing: {
            PoruchIcon(glyph: PoruchIcons.chevronRight, size: 16).foregroundStyle(Palette.inkTertiary)
        }
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
    /// Назва події (а не службового рядка) — засічками, як у постері.
    var brandTitle = false
    @ViewBuilder let tile: Tile
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: Space.sm) {
            Button(action: open) {
                HStack(spacing: Space.md) {
                    tile
                    VStack(alignment: .leading, spacing: 2) {
                        if let overline {
                            Text(overline).font(PoruchFont.overline).kerning(1.0).foregroundStyle(Palette.inkTertiary).lineLimit(1)
                        }
                        Text(title).font(brandTitle ? PoruchFont.brandTitle3 : PoruchFont.cardName).kerning(brandTitle ? -0.1 : -0.2)
                            .foregroundStyle(Palette.ink).multilineTextAlignment(.leading).lineLimit(2)
                        if let subtitle, !subtitle.isEmpty {
                            Text(subtitle).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    if chat == nil { trailing }
                }.contentShape(Rectangle())
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

/// Найближчий план великою карткою, як посадковий талон: відлік, назва, місце й дії — маршрут, чат, запити.
private struct NextPlanCard: View {
    let row: PersonalRow
    let open: () -> Void
    let chat: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    private var event: Event { row.event }

    private var today: Bool { parseEventDate(event.startsAt).map(Calendar.current.isDateInToday) == true }

    /// Відлік лише для сьогоднішнього: «через 25 год» про завтрашнє нічого не каже.
    private var overline: String { today ? countdownOverline(event) : cardOverline(event) }

    /// Остання репліка чату, коли є нове; інакше моя роль і місце.
    private var chatPreview: String? {
        guard let unread = row.chat, !unread.lastBody.isEmpty else { return nil }
        let author = unread.lastAuthorName.isEmpty ? Copy.chat_member : unread.lastAuthorName
        return "\(author): «\(unread.lastBody.replacingOccurrences(of: "\n", with: " "))»"
    }

    private var subtitle: String {
        chatPreview ?? [row.organizing ? Copy.home_role_organizer : Copy.going, event.placeLabel].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Button(action: open) {
                HStack(alignment: .top, spacing: Space.lg) {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(overline).font(PoruchFont.overline).kerning(1.0).foregroundStyle(Palette.accentText).lineLimit(1)
                        Text(event.displayTitle).font(PoruchFont.brandTitle2).kerning(-0.2).foregroundStyle(Palette.ink)
                            .multilineTextAlignment(.leading).lineLimit(3)
                        // Місце в один рядок: повна адреса живе в «Маршруті», а не в підписі.
                        Text(subtitle).font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary)
                            .multilineTextAlignment(.leading).lineLimit(chatPreview == nil ? 1 : 2)
                    }
                    Spacer(minLength: 0)
                    EventThumbnail(event: event, glyphSize: 30, maxDimension: 88)
                        .frame(width: 88, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: Corner.md, style: .continuous))
                }.contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(pressedScale: 1))
            .accessibilityElement(children: .combine)
            // Великий шрифт: дії одна під одною, як у «Моїх подіях», — три в ряд обрізали б «Маршрут» до «Ма…».
            let actions = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: Space.sm)) : AnyLayout(HStackLayout(spacing: Space.sm))
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
        .padding(Space.lg)
        .cardSurface(radius: Corner.xl)
    }
}

/// Своя подія: категорія плиткою, час, назва. Праворуч — про що просять: нове в чаті, запити, або просто «Ви йдете».
private struct PlanRow: View {
    let row: PersonalRow
    let open: () -> Void
    let chat: () -> Void

    private var event: Event { row.event }

    /// Моя роль у події; після кінця вона нічого не каже.
    private var role: (String, BadgeTone)? {
        if event.isCancelled { return (Copy.cancelled_short, .danger) }
        if event.hasEnded(now: nowInstant()) { return nil }
        return row.organizing ? (Copy.home_role_organizer, .brand) : (Copy.going, .success)
    }

    /// Праворуч зайнято лічильником чи запитами — роль переїжджає до дати.
    private var overline: String {
        guard row.chat != nil || row.requests > 0, let role else { return cardOverline(event) }
        return cardOverline(event) + " · " + role.0.uppercased(with: Locale(identifier: "uk_UA"))
    }

    private var subtitle: String? {
        guard let chat = row.chat else { return event.placeLabel }
        let author = chat.lastAuthorName.isEmpty ? Copy.chat_member : chat.lastAuthorName
        let body = chat.lastBody.replacingOccurrences(of: "\n", with: " ")
        return body.isEmpty ? Copy.new_messages_count("\(chat.unread)") : "\(author): «\(body)»"
    }

    /// Лічильник — кнопка в чат, поки праворуч не зайняли запити: на них теж чекає людина, і вони важливіші.
    private var chatButton: (count: Int, open: () -> Void)? {
        guard let unread = row.chat, row.requests == 0 else { return nil }
        return (Int(unread.unread), chat)
    }

    var body: some View {
        YourRow(overline: overline, title: event.displayTitle, subtitle: subtitle, open: open, chat: chatButton, brandTitle: true) {
            EventThumbnail(event: event, glyphSize: 24, maxDimension: 52)
                .frame(width: yourTile, height: yourTile)
                .clipShape(RoundedRectangle(cornerRadius: Corner.sm, style: .continuous))
        } trailing: {
            if event.isCancelled {
                TicketStamp(text: Copy.cancelled_short, tone: .danger)
            } else if row.requests > 0 {
                StatusBadge(
                    text: Copy.requests_count(Int(row.requests)),
                    tone: .accent, glyph: PoruchIcons.personAdd
                )
            } else if let role {
                StatusBadge(text: role.0, tone: role.1)
            }
        }
    }
}
