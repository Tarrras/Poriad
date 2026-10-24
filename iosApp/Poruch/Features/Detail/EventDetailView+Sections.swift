import SwiftUI
import PhotosUI
import EventKit
import Shared

/// Маршрут деталей події: для шляху стосу й для шторки.

// Секції деталей: усе між обкладинкою й нижньою панеллю дії. Розрізано з EventDetailView.swift.

extension EventDetailView {
    /// Місце обкладинки у стрічці: саму картинку малює тло під нею (див. `detail`). Стрічка
    /// починається під верхнім відступом, тож тут лише решта висоти. Кнопки згори, бейджі внизу,
    /// на фото, де вже темніє градієнт: тому вони в стилі «на фото».
    func hero(_ event: Event, _ view: DetailScreenState) -> some View {
        Color.clear
            // Низ обкладинки на `Corner.xl` ховається під аркушем секцій.
            .frame(height: max(heroHeight - topInset - Corner.xl, 0)).frame(maxWidth: .infinity)
            // Назва лежить на затемненні обкладинки, як на великій картці головної: одна сцена, а не фото з підписом.
            // Текст їде зі стрічкою, а смуга статусу з'являється лише з аркушем: назва гасне, поки не дійшла до годинника.
            .overlay(alignment: .bottomLeading) {
                HeroTextFade(scroll: scroll) {
                    VStack(alignment: .leading, spacing: Space.md) {
                        if let inviter = view.inviter { InviterLine(inviter: inviter) }
                        if let stamp = coverState(event, view) {
                            TicketStamp(text: stamp.0, tone: stamp.1, glyph: stamp.2, onFill: true)
                        }
                        VStack(alignment: .leading, spacing: Space.sm) {
                            // Дата й час — на корінці квитка внизу екрана, тож над назвою їх не повторюємо.
                            Text(event.displayTitle).font(PoruchFont.brandDisplay).kerning(-0.5).foregroundStyle(.white)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(coverMeta(event, view)).font(PoruchFont.subhead).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                        }
                    }
                    .padding(.horizontal, Space.page).padding(.bottom, Space.xl)
                }
            }
            .overlay(alignment: .top) {
                HStack(spacing: Space.sm) {
                    ScrimButton(glyph: PoruchIcons.chevronLeft, label: Copy.back) { dismiss() }
                    Spacer()
                    ScrimButton(
                        glyph: view.saved ? PoruchIcons.bookmarkFilled : PoruchIcons.bookmark,
                        label: view.saved ? Copy.unsave : Copy.save
                    ) { actions.toggleSaved(event) }
                }.padding(Space.page)
            }
    }

    /// Стан квитка — штампом над назвою, лише коли з ним щось сталось (як на квитках стрічки). Жанр і джерело афіші —
    /// тихим рядком під назвою (`coverMeta`): пігулки були окремою мовою міток, а жанр ще й надрукований на корінці панелі.
    func coverState(_ event: Event, _ view: DetailScreenState) -> (String, BadgeTone, PoruchGlyph?)? {
        if view.cancelled { return (Copy.cancelled_short, .danger, nil) }
        if let listing = view.listing { return listingStamp(listing) }
        if view.organizer { return (Copy.you_organize, .neutral, nil) }
        // Після кінця лишається лише факт участі: черга й місця вже нічого не значать.
        if view.ended { return view.room?.joined == true ? (Copy.went, .neutral, PoruchIcons.check) : nil }
        if view.room?.joined == true { return (Copy.going, .success, PoruchIcons.check) }
        if view.waitlisted { return (Copy.in_queue, .accent, PoruchIcons.queue) }
        if view.room?.awaitingApproval == true { return (Copy.request_pending, .accent, PoruchIcons.queue) }
        if eventScarce(event), let room = view.room { return (Copy.seats_left("\(room.seatsLeft)"), .accent, nil) }
        return nil
    }

    /// «Стендап · Афіша · Badseller»: афіша завжди підписана джерелом — атрибуція обов'язкова.
    func coverMeta(_ event: Event, _ view: DetailScreenState) -> String {
        var parts = [categoryName(event.category)]
        if let listing = view.listing {
            parts.append(Copy.listing_badge(listing.sellerNames))
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Для кого подія, на картці, а не через відмову сервера.
    func restrictions(_ room: Gathering) -> some View {
        HStack(spacing: Space.sm) {
            if let limit = ageLimitLabel(room) { StatusBadge(text: limit, tone: .brand, glyph: PoruchIcons.person) }
            if room.approvalRequired { StatusBadge(text: Copy.approval_badge, tone: .neutral, glyph: PoruchIcons.lock) }
        }
    }

    /// Дати прокату. Лише коли сеансів більше одного. Скасований лишається на місці, позначеним.
    func sessionRail(_ event: Event, _ sessions: [EventSession]) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader(title: Copy.sessions_title)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.sm) {
                        ForEach(sessions, id: \.id) { session in
                            sessionChip(session, selected: session.id == event.id).id(session.id)
                        }
                    }
                }
                // Смуга від краю до краю, відступ несе вміст.
                .railContentPadding()
                .padding(.horizontal, -Space.page)
                // Обраний сеанс має бути видно одразу, навіть якщо він шостий.
                .onAppear { proxy.scrollTo(event.id, anchor: .center) }
            }
        }
        // Без zIndex дотики до стрічки перехоплює сусідня секція.
        .zIndex(1)
    }

    func sessionChip(_ session: EventSession, selected: Bool) -> some View {
        let label = sessionLabel(session)
        let started = parseEventDate(session.startsAt).map { $0 <= Date() } ?? false
        let status = session.cancelled ? Copy.cancelled_short : started ? Copy.session_started : nil
        return Button {
            if !selected { screen.pickSession(session.id) }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(label.day).font(PoruchFont.caption).lineLimit(1)
                    .foregroundStyle(selected ? Palette.surface.opacity(0.8) : Palette.inkSecondary)
                Text(label.hour).font(PoruchFont.cardName).strikethrough(session.cancelled)
                    .foregroundStyle(selected ? Palette.surface : Palette.ink)
                if let status {
                    Text(status).font(PoruchFont.caption).lineLimit(1)
                        .foregroundStyle(session.cancelled ? Palette.danger : selected ? Palette.surface.opacity(0.8) : Palette.inkTertiary)
                }
            }
            .padding(.horizontal, Space.md).padding(.vertical, Space.sm)
            .frame(minWidth: 96, alignment: .leading)
            .background(selected ? Palette.ink : Palette.surface,
                        in: RoundedRectangle(cornerRadius: Corner.sm, style: .continuous))
            .opacity(session.cancelled && !selected ? 0.6 : 1)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel([label.day, label.hour, status].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Хто виступає: імена тапаються й ведуть на екран артиста стеком; ведучий підписаний. Повний склад, без «та ще N» картки.
    func lineup(_ event: Event) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader(title: Copy.lineup_title)
            FlowLayout(spacing: Space.sm) {
                ForEach(event.artists, id: \.id) { artist in
                    NavigationLink(value: ArtistRoute(id: artist.id, name: artist.name, kind: artist.kind)) {
                        Text(artist.role == .host ? Copy.artist_host("\(artist.name)") : artist.name)
                            .font(PoruchFont.label).foregroundStyle(Palette.ink)
                            .padding(.horizontal, Space.lg).frame(minHeight: 44)
                            .background(Palette.surface, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
    }

    /// Факти про подію сіткою два на два, як картка дня в Moonly: підпис над значенням, без гліфів.
    func facts(_ event: Event) -> some View {
        var cells: [(String, String)] = [
            (Copy.date, eventDate(event)),
            (Copy.where, [event.city, event.address].filter { !$0.isEmpty }.joined(separator: " · "))
        ]
        if let room = event.gathering {
            cells.append((Copy.organizer_short, room.organizerName.isEmpty ? Copy.organizer_short : room.organizerName))
            cells.append((Copy.capacity_label, Copy.attendees_short("\(room.attendeeCount)", "\(room.capacity)")))
        }
        return LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)], spacing: Space.xl) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(cell.0.uppercased()).font(PoruchFont.overline).kerning(1.0).foregroundStyle(Palette.inkTertiary)
                    Text(cell.1).font(PoruchFont.title3).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }.padding(Space.xl).cardSurface()
    }

    /// Люди події: організатор і ті, хто йде. Рядок відкриває картку людини — так організатор і
    /// учасники бачать одне одного. Ростер віддає лише своїм, решта бачить тільки організатора.
    func people(_ room: Gathering, _ view: DetailScreenState) -> some View {
        let organizerAvatar = view.organizerAvatar
        let shown = showAllPeople ? view.attendees : Array(view.attendees.prefix(rosterCollapsed))
        return VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader(title: Copy.attendees_going)
            GroupedRows {
                personRow(room.organizerName.isEmpty ? Copy.organizer_short : room.organizerName,
                          avatar: organizerAvatar, caption: Copy.organizer_short, userId: room.organizerId, view)
                ForEach(shown, id: \.userId) { person in
                    Divider().overlay(Palette.hairline).padding(.leading, Space.lg + 40 + Space.md)
                    personRow(person.name.isEmpty ? Copy.chat_member : person.name, avatar: person.avatarUrl, caption: nil, userId: person.userId, view)
                }
                if !showAllPeople && view.attendees.count > rosterCollapsed {
                    Divider().overlay(Palette.hairline).padding(.leading, Space.lg)
                    Button { showAllPeople = true } label: {
                        Text("\(Copy.attendees_show_all) · \(view.attendees.count)").font(PoruchFont.button).foregroundStyle(Palette.ink)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(Space.lg).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            // Гість і сторонній бачать лише число: імена — межа RLS.
            if view.attendees.isEmpty && room.attendeeCount > 0 {
                Text(Copy.going_of("\(room.attendeeCount)", "\(room.capacity)")).font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary)
            }
        }
    }

    func openPerson(_ userId: String) {
        showingPerson = true
        model.app.openPerson(userId: userId)
    }

    func personRow(_ name: String, avatar: String?, caption: String?, userId: String, _ view: DetailScreenState) -> some View {
        Button { if view.signedIn { openPerson(userId) } else { auth = .general } } label: {
            HStack(spacing: Space.md) {
                Avatar(name: name, url: avatar, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(PoruchFont.cardName).foregroundStyle(Palette.ink).lineLimit(1)
                    if let caption { Text(caption).font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary) }
                }
                Spacer(minLength: 0)
                PoruchIcon(glyph: PoruchIcons.chevronRight, size: 16).foregroundStyle(Palette.inkTertiary)
            }
            .padding(.horizontal, Space.lg).padding(.vertical, Space.md).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Copy.person_open("\(name)"))
    }

    /// Ряд круглих дій із підписами, як панель під картою дня в Moonly.
    func externalActions(_ event: Event, _ view: DetailScreenState) -> some View {
        HStack(spacing: Space.sm) {
            Button { actions.openCalendar() } label: {
                RoundAction(title: Copy.calendar_short, enabled: !view.cancelled) { PoruchIcon(glyph: PoruchIcons.calendar, size: 20) }
            }.buttonStyle(PressableStyle()).disabled(view.cancelled)
            Button { SystemActions.openInMaps(event) } label: {
                RoundAction(title: Copy.rate_tag_route) { PoruchIcon(glyph: PoruchIcons.directions, size: 20) }
            }.buttonStyle(PressableStyle())
            // Поділитися подією — і є покликати (docs/invites.md). Скасовану чи минулу — просто поділитися.
            if view.canInvite {
                Button { invite(event) } label: {
                    RoundAction(title: Copy.invite) {
                        if inviting { ProgressView() } else { PoruchIcon(glyph: PoruchIcons.personAdd, size: 20) }
                    }
                }.buttonStyle(PressableStyle())
            } else {
                ShareLink(item: SystemActions.shareText(for: event)) {
                    RoundAction(title: Copy.share) { PoruchIcon(glyph: PoruchIcons.share, size: 20) }
                }.buttonStyle(PressableStyle())
                .simultaneousGesture(TapGesture().onEnded { model.app.eventShared() })
            }
            Button { screen.handedOff = true; model.app.selectEvent(id: screen.cardID()); openMap() } label: {
                RoundAction(title: Copy.on_map) { PoruchIcon(glyph: PoruchIcons.map, size: 20) }
            }.buttonStyle(PressableStyle())
        }
    }

    /// Посилання дає спільний шар — особисте з входом, звичайне гостю чи при збої — і сам рахує `share`.
    func invite(_ event: Event) {
        guard !inviting else { return }
        inviting = true
        Task {
            let link = (try? await model.app.inviteLink(eventId: event.id)) ?? EventLinks.shared.url(eventId: event.id)
            inviting = false
            sharing = ShareText(text: SystemActions.inviteText(for: event, link: link))
        }
    }

    /// Місце події. Мініатюра без жестів, тап веде на велику мапу.
    func venue(_ event: Event, _ view: DetailScreenState) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            // В афіші це адреса залу, а не «місце зустрічі».
            SectionHeader(title: event.isCommunity ? Copy.venue : Copy.rate_tag_place)
            ZStack(alignment: .bottomTrailing) {
                EventMapSnapshot(latitude: event.latitude, longitude: event.longitude, category: event.category)
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: Corner.md, style: .continuous))
                .allowsHitTesting(false)
                StatusBadge(text: Copy.show_map, tone: .neutral, glyph: PoruchIcons.map).padding(Space.sm)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                // Вибір до переходу, щоб мапа навелась. Для другої дати прокату — картка представника.
                // Без `dismiss()`: деталі закриває `openMap` разом зі стеком. Pop лише верхніх деталей
                // показував нижчі, і їхній `.task` знову обирав свою подію замість цієї.
                model.app.selectEvent(id: model.app.cardIdOf(id: event.id))
                screen.handedOff = true; openMap()
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Copy.show_map)
            if FollowRules.shared.canFollowPlace(event: event), let placeId = event.placeId {
                followPlace(event, placeId, view)
            }
        }
    }

    /// «Стежити» за закладом афіші: пуш, коли тут зʼявиться нове. Гостя — на вхід, пуш прив'язаний до акаунта.
    func followPlace(_ event: Event, _ placeId: String, _ view: DetailScreenState) -> some View {
        let following = view.followingPlace
        return HStack(spacing: Space.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.placeLabel).font(PoruchFont.cardName).kerning(-0.2).foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.leading).lineLimit(2)
                Text(Copy.follow_place_hint).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary)
            }
            Spacer(minLength: Space.sm)
            FollowPill(following: following) {
                guard view.signedIn else { auth = .follow; return }
                model.app.setFollowing(kind: .place, targetId: placeId, name: event.placeLabel, following: !following)
            }
        }
        .padding(.horizontal, Space.lg).padding(.vertical, Space.md).frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    /// Безпека: чи встигнеш до комендантської і куди йти під час тривоги. Правила Мінкульту з 11.09.2026
    /// вимагають заздалегідь казати учасникам про найближче укриття. Нема даних міста — нема секції.
    @ViewBuilder
    func safety() -> some View {
        let shelters = screen.state.safety?.shelters ?? []
        let curfew = screen.state.curfew
        if !shelters.isEmpty || curfew != nil {
            VStack(alignment: .leading, spacing: Space.sm) {
                SectionHeader(title: Copy.safety_title)
                VStack(spacing: 0) {
                    if let curfew {
                        // Година й менше до комендантської — уже привід планувати дорогу, тож колір попередження.
                        let tight = curfew.minutesLeft <= 60
                        HStack(spacing: Space.md) {
                            PoruchIcon(glyph: PoruchIcons.moon, size: 19)
                            Text(curfew.minutesLeft == 0
                                 ? Copy.curfew_during("\(curfew.endsAt)", "\(curfew.curfew.starts)")
                                 : Copy.curfew_left("\(curfew.endsAt)", "\(curfew.curfew.starts)", "\(durationWords(Int(curfew.minutesLeft)))"))
                                .font(PoruchFont.bodyText).multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(tight ? Palette.danger : Palette.inkSecondary)
                        .padding(.horizontal, Space.lg).padding(.vertical, Space.md)
                    }
                    ForEach(Array(shelters.enumerated()), id: \.offset) { index, shelter in
                        if index > 0 || curfew != nil { Divider().overlay(Palette.hairline) }
                        Button { SystemActions.openInMaps(latitude: shelter.latitude, longitude: shelter.longitude, label: shelter.address) } label: {
                            HStack(spacing: Space.md) {
                                PoruchIcon(glyph: shelter.kind == .metro ? PoruchIcons.subway : PoruchIcons.shield, size: 20)
                                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.inkTertiary)
                                VStack(alignment: .leading, spacing: Space.xs) {
                                    Text(Copy.shelter_kind_distance("\(shelterLabel(shelter.kind))", "\(shelter.distanceMeters)"))
                                        .font(PoruchFont.overline).kerning(1.0).foregroundStyle(Palette.inkTertiary)
                                    Text(shelter.address).font(PoruchFont.cardName).kerning(-0.2).foregroundStyle(Palette.ink)
                                        .multilineTextAlignment(.leading).lineLimit(2)
                                    let extras = [shelter.hours, shelter.accessible ? Copy.shelter_accessible : nil].compactMap { $0 }
                                    if !extras.isEmpty {
                                        Text(extras.joined(separator: " · ")).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary)
                                    }
                                }
                                Spacer(minLength: 0)
                                PoruchIcon(glyph: PoruchIcons.chevronRight, size: 15).foregroundStyle(Palette.inkTertiary)
                            }
                            .padding(.horizontal, Space.lg).padding(.vertical, Space.md)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityElement(children: .combine)
                        .accessibilityHint(Copy.a11y_route_shelter)
                    }
                }
                .cardSurface()
                // Ліцензія CC BY вимагає вказати джерело.
                if !shelters.isEmpty {
                    Text(Copy.shelters_source)
                        .font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary)
                }
            }
        }
    }

    func shelterLabel(_ kind: ShelterKind) -> String {
        switch kind {
        case .metro: Copy.shelter_metro
        case .underpass: Copy.shelter_underpass
        case .parking: Copy.shelter_parking
        default: Copy.shelter_basement
        }
    }

    func durationWords(_ minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return Copy.duration_minutes("\(rest)") }
        return rest == 0 ? Copy.duration_hours("\(hours)") : Copy.duration_hours("\(hours)") + " " + Copy.duration_minutes("\(rest)")
    }

    /// Інші події на цій точці. Заголовок — місце (назва закладу, коли є), тому рядку досить дати й назви.
    /// Окремий екран поверх, а не підміна: «назад» має повертати сюди; `.task` вище перечитає подію після повернення.
    /// Згорнуто після опису: у великого закладу десятки подій, і розгорнутий список відсував би решту сторінки.
    func othersHereSection(_ othersHere: [EventIndexEntry], placeName: String?) -> some View {
        // Значенням, не через `self`: вигляд `Equatable` за id, тож замикання підпису кнопки, яке читає лише
        // `self.showOthersHere`, SwiftUI вважає незмінним і шеврон не повертає.
        let expanded = showOthersHere
        return VStack(alignment: .leading, spacing: Space.sm) {
            Button { withMotion { showOthersHere.toggle() } } label: {
                HStack(spacing: Space.sm) {
                    Text(placeName.map { Copy.others_here_at("\($0)") } ?? Copy.others_here).font(PoruchFont.brandTitle2).kerning(-0.2)
                        .foregroundStyle(Palette.ink).multilineTextAlignment(.leading)
                    Spacer(minLength: Space.sm)
                    Text("\(othersHere.count)").font(PoruchFont.label).foregroundStyle(Palette.inkSecondary).monospacedDigit()
                    PoruchIcon(glyph: PoruchIcons.chevronDown, size: 16).foregroundStyle(Palette.inkTertiary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(showOthersHere ? Copy.expanded : Copy.collapsed)
            .accessibilityHint(Copy.a11y_events_count("\(othersHere.count)"))
            if showOthersHere { othersHereList(othersHere) }
        }
    }

    func othersHereList(_ othersHere: [EventIndexEntry]) -> some View {
            VStack(spacing: 0) {
                ForEach(othersHere, id: \.id) { other in
                    let label = sessionLabel(EventSession(id: other.id, startsAt: other.startsAt, timeZone: other.timeZone, cancelled: false))
                    NavigationLink(value: EventRoute(id: other.id)) {
                        HStack(spacing: Space.md) {
                            VStack(alignment: .leading, spacing: Space.xs) {
                                Text("\(label.day) · \(label.hour)").font(PoruchFont.overline).kerning(1.0).foregroundStyle(Palette.inkTertiary)
                                Text(TitleRules.shared.display(title: other.title)).font(PoruchFont.brandTitle3).kerning(-0.1).foregroundStyle(Palette.ink)
                                    .multilineTextAlignment(.leading).lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            PoruchIcon(glyph: PoruchIcons.chevronRight, size: 15).foregroundStyle(Palette.inkTertiary)
                        }
                        .padding(.horizontal, Space.lg).padding(.vertical, Space.md)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityElement(children: .combine)
                }
            }
            .cardSurface()
    }

    /// Чат учасників. Кнопка веде не в браузер, а на попередження: посилання чуже, ми його не
    /// перевіряли, і людина має це знати до того, як вийде із застосунку.
    func contact(_ view: DetailScreenState) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader(title: Copy.contact_section)
            if view.hasChat {
                // Повний екран у стеку, а не шторка: чат читають довго.
                NavigationLink(value: ChatRoute(id: view.event?.id ?? "")) {
                    HStack(spacing: Space.sm) {
                        PoruchIcon(glyph: PoruchIcons.chat, size: 18)
                        Text(Copy.contact_label).font(PoruchFont.button).lineLimit(1)
                    }
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, Space.xxl).frame(height: 52).frame(maxWidth: .infinity)
                    .background(Palette.brandContainer, in: buttonShape)
                }
                .buttonStyle(PressableStyle())
                Text(Copy.chat_open_hint)
                    .font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary)
            }
            if view.contactURL != nil {
                SecondaryButton(title: Copy.contact_open, glyph: PoruchIcons.link) { openingContact = true }
                    .frame(maxWidth: .infinity)
                Text(Copy.contact_members_hint)
                    .font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary)
            }
        }
    }

    /// Запити на участь. На екрані деталей, бо організатор відповідає, дивлячись на свою подію.
    func joinRequests(_ event: Event, _ view: DetailScreenState) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader(title: Copy.request_notification_channel)
            ForEach(view.requests, id: \.userId) { person in
                HStack(spacing: Space.md) {
                    // Імʼя й фото — вхід у картку: вирішувати, дивлячись на людину, а не на імʼя.
                    Button { openPerson(person.userId) } label: {
                        HStack(spacing: Space.md) {
                            Avatar(name: person.name, url: person.avatarUrl, size: 36)
                            // Поступається імʼя, а не дії: з більшим кеглем кнопок «Прийняти» переносилось на два рядки.
                            Text(person.name.isEmpty ? Copy.chat_member : person.name)
                                .font(PoruchFont.cardName).foregroundStyle(Palette.ink).lineLimit(1)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel(Copy.person_open("\(person.name)"))
                    Spacer(minLength: 0)
                    // Поля й тло — у мітці: поза міткою SwiftUI зараховує до дотику лише саме слово.
                    Button { model.app.declineMember(eventId: event.id, userId: person.userId) } label: {
                        Text(Copy.decline).font(PoruchFont.button).foregroundStyle(Palette.inkSecondary).lineLimit(1).fixedSize()
                            .tapTarget()
                    }.buttonStyle(.plain)
                    Button { model.app.approveMember(eventId: event.id, userId: person.userId) } label: {
                        Text(Copy.approve).font(PoruchFont.button).foregroundStyle(Palette.onBrand).lineLimit(1).fixedSize()
                            .padding(.horizontal, Space.lg).frame(height: 40)
                            .background(Palette.brand, in: buttonShape)
                            .tapTarget()
                    }.buttonStyle(PressableStyle())
                }.padding(Space.lg).frame(maxWidth: .infinity, alignment: .leading).cardSurface()
            }
        }
    }

    /// Скарга й блокування внизу сторінки, не в меню: важка скарга — неподана скарга.
    func safetyActions(_ view: DetailScreenState) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Divider().overlay(Palette.hairline)
            HStack(spacing: Space.lg) {
                Button { if view.signedIn { reporting = .event } else { auth = .general } } label: { Text(Copy.chat_report).tapTarget() }
                // Блокувати нема кого без людини; скарга на афішу лишається.
                if view.event?.organizerId != nil {
                    Button { if view.signedIn { blocking = true } else { auth = .general } } label: { Text(Copy.block_user).tapTarget() }
                }
                Spacer(minLength: 0)
            }.font(PoruchFont.button).foregroundStyle(Palette.inkSecondary)
        }
    }

    func organizerActions(_ view: DetailScreenState) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Divider().overlay(Palette.hairline)
            // Час, місце й місткість супутника тримає сервер; після початку сервер не приймає правок. Лишається скасувати.
            let editable = view.companionOf == nil && !view.started
            if editable {
                PhotosPicker(selection: $photo, matching: .images) {
                    Label(Copy.add_photo, systemImage: "camera")
                        .font(PoruchFont.subhead.weight(.semibold)).foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity).frame(minHeight: 52)
                        .background(Palette.brandContainer, in: buttonShape)
                }.disabled(view.mutating)
            }
            if let error = actions.photoError {
                Text(error).font(PoruchFont.caption).foregroundStyle(Palette.danger)
            }
            // Збір: організатор міняє лише час (R7б).
            if view.canMoveMeet, let event = view.event {
                SecondaryButton(title: Copy.meet_change, glyph: PoruchIcons.clock) { movingMeet = MeetTarget(at: event.startsAt) }
            }
            HStack(spacing: Space.md) {
                if editable { SecondaryButton(title: Copy.edit, glyph: PoruchIcons.edit) { editing = true } }
                SecondaryButton(title: Copy.delete_account_cancel, glyph: PoruchIcons.close, tone: Palette.danger) { cancelling = true }
            }
        }
    }

    /// Панель дії — квиток у руці: місця чи ціна й дії на поверхні, а корінець із часом, днем і кольором жанру — справа.
    /// Дата на екрані одна, тут; обкладинка її не повторює.
    func stickyBar(_ event: Event, _ view: DetailScreenState) -> some View {
        Ticket(stubColor: ticketStub(event), stubLength: 84, radius: Corner.xl, surface: Palette.surfaceRaised) {
            VStack(alignment: .leading, spacing: Space.md) {
                if view.canSeekCompany {
                    // Афіша: ціна й квиток в один рядок — квиток купують на чужому сайті, тож він другорядний.
                    HStack(spacing: Space.md) {
                        summary(view)
                        Spacer(minLength: 0)
                        if view.action != .none { secondaryAction(event, view).fixedSize(horizontal: true, vertical: false) }
                    }
                } else {
                    // Зустріч: пояснення («Організатор підтверджує кожного», «Лишилось 2 місця») — окремим рядком на всю
                    // ширину, а дія під ним. Поруч із кнопкою воно обрізалось саме в момент рішення.
                    summary(view)
                    // Кнопки може не бути: у знятої афіші й афіші без посилання нема куди вести.
                    if view.action != .none { primaryAction(event, view) }
                }
                // Серце продукту — люди: на афіші головна дія — «Шукаю компанію», на всю ширину під ціною й квитком.
                if view.canSeekCompany {
                    PrimaryButton(title: Copy.companion_seek, glyph: PoruchIcons.social, enabled: !view.mutating) {
                        if view.signedIn { seekingCompany = true } else { auth = .company }
                    }
                    .coachTarget(.companion)
                }
            }
            .padding(.horizontal, Space.lg).padding(.vertical, Space.md)
        } stub: {
            StubTime(event: event)
        }
        // Плаває над сторінкою: дія під пальцем, а не смуга на всю ширину.
        .lifted(Elevation.overlay)
        .padding(.horizontal, Space.md)
    }
}

extension EventDetailView {
    func primaryAction(_ event: Event, _ view: DetailScreenState) -> some View {
        PrimaryButton(
            title: view.action.title,
            tone: view.action == .leave ? Palette.success : view.action == .leaveWaitlist ? Palette.accentText : nil,
            loading: view.mutating,
            enabled: view.action.isEnabled && !view.mutating
        ) {
            if !actions.perform(view.action, on: event, signedIn: view.signedIn) { auth = .join }
        }
    }

    private func summary(_ view: DetailScreenState) -> some View {
        Text(view.seatsSummary).font(PoruchFont.subhead)
            .foregroundStyle(view.event?.isCalledOff == true ? Palette.danger : Palette.inkSecondary)
            .lineLimit(3).fixedSize(horizontal: false, vertical: true)
    }

    /// Та сама дія, що `primaryAction`, тихішою кнопкою: квиток поруч із «Шукаю компанію».
    func secondaryAction(_ event: Event, _ view: DetailScreenState) -> some View {
        SecondaryButton(title: view.action.title, enabled: view.action.isEnabled && !view.mutating) {
            if !actions.perform(view.action, on: event, signedIn: view.signedIn) { auth = .join }
        }
    }

    /// Квитки афіші (R8–R10): стан, коли з подією щось сталось, і продавці — кожен своїм рядком з ціною й посиланням.
    /// Не в силі — «Якщо купили квиток» з усіма продавцями, де могли купити. Під ними «Перевірено…» і обіцянка «Зберегти».
    func tickets(_ event: Event, _ listing: Listing, _ view: DetailScreenState) -> some View {
        let refund = listing.isWithdrawn
        let sellers = refund ? listing.sellers : listing.sellers.filter { $0.live }
        let stamp = view.cancelled ? (Copy.cancelled_short, BadgeTone.danger, nil) : listingStamp(listing)
        return VStack(alignment: .leading, spacing: Space.md) {
            if let stamp {
                TicketStamp(text: stamp.0, tone: stamp.1)
                if let hint = listing.stateHint(event) {
                    Text(hint).font(PoruchFont.bodyText).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                }
            }
            if !sellers.isEmpty {
                Text((refund ? Copy.sellers_refund_title : Copy.listing_price_label).uppercased())
                    .font(PoruchFont.overline).kerning(1.0).foregroundStyle(Palette.inkTertiary)
                VStack(spacing: 0) {
                    ForEach(Array(sellers.enumerated()), id: \.offset) { index, offer in
                        if index > 0 { Divider().overlay(Palette.hairline) }
                        Button { actions.openSeller(offer, of: event, from: refund ? "refund" : "sellers") } label: {
                            HStack(spacing: Space.md) {
                                Text(offer.sourceName).font(PoruchFont.cardName).foregroundStyle(Palette.ink)
                                Spacer(minLength: Space.sm)
                                if !refund { Text(offerPrice(offer)).font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary) }
                                PoruchIcon(glyph: PoruchIcons.chevronRight, size: 15).foregroundStyle(Palette.inkTertiary)
                            }
                            .frame(minHeight: 48).contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle(pressedScale: 1))
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            if let checked = view.checked {
                Text(checkedText(checked)).font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary)
            }
            // Обіцянка «Зберегти» (R9): зберегти = стежити за змінами, з квитком чи без.
            if !refund && !view.ended {
                Divider().overlay(Palette.hairline)
                Button { actions.toggleSaved(event) } label: {
                    HStack(spacing: Space.md) {
                        PoruchIcon(glyph: view.saved ? PoruchIcons.bookmarkFilled : PoruchIcons.bookmark, size: 20).foregroundStyle(Palette.ink)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(view.saved ? Copy.saved_short : Copy.save).font(PoruchFont.cardName).foregroundStyle(Palette.ink)
                            Text(Copy.save_promise).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 48).contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle(pressedScale: 1))
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(view.saved ? .isSelected : [])
            }
        }
        .padding(Space.lg).frame(maxWidth: .infinity, alignment: .leading).cardSurface()
    }

    /// Афішу перенесли, збір чекає рішення (R7а). Організатор — три відповіді; учасник — що рішення за організатором.
    /// Інша дата — «Скасувати збір» помітніше: вільного вечора може не бути.
    func meetDecision(_ event: Event, _ parent: CompanionParent, _ pending: PendingMeet, _ view: DetailScreenState) -> some View {
        let zone = event.timeZone
        let newStart = parent.startsAt.map { meetWhen($0, ref: nil, zone: zone) } ?? ""
        let proposed = meetWhen(pending.proposedAt, ref: event.startsAt, zone: zone)
        let otherDay = !sameDay(pending.proposedAt, event.startsAt, zone: zone)
        return VStack(alignment: .leading, spacing: Space.md) {
            TicketStamp(text: Copy.state_moved, tone: .accent)
            if view.organizer {
                Text(Copy.meet_decision_ask(newStart, meetWhen(event.startsAt, ref: event.startsAt, zone: zone), proposed))
                    .font(PoruchFont.bodyText).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                PrimaryButton(title: Copy.meet_move_to(proposed), loading: view.mutating, enabled: !view.mutating) {
                    model.app.moveCompanion(id: event.id, meetAt: pending.proposedAt)
                }
                HStack(spacing: Space.md) {
                    SecondaryButton(title: Copy.meet_other_time, enabled: !view.mutating) { movingMeet = MeetTarget(at: pending.proposedAt) }
                    if otherDay {
                        SecondaryButton(title: Copy.meet_cancel, tone: Palette.danger, enabled: !view.mutating) { cancelling = true }
                    }
                }
                if !otherDay {
                    Button(Copy.meet_cancel) { cancelling = true }
                        .font(PoruchFont.button).foregroundStyle(Palette.danger).tapTarget()
                }
                Text(Copy.meet_decision_deadline(meetWhen(pending.decideBy, ref: nowInstant().description, zone: zone), proposed))
                    .font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary)
            } else {
                Text(Copy.meet_decision_wait(newStart))
                    .font(PoruchFont.bodyText).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.lg).frame(maxWidth: .infinity, alignment: .leading).cardSurface()
    }

    /// «Купили? Стежитимемо за змінами» після повернення від продавця (R9): раз на подію, над панеллю дії.
    func boughtCard(_ event: Event, _ view: DetailScreenState) -> some View {
        HStack(spacing: Space.md) {
            Text(Copy.bought_prompt).font(PoruchFont.subhead).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(Copy.bought_prompt_save) {
                boughtPrompt = false
                model.app.boughtPromptAnswered(saved: true)
                if !view.saved { actions.toggleSaved(event) }
            }
            .font(PoruchFont.button).foregroundStyle(Palette.onBrand)
            .padding(.horizontal, Space.lg).frame(minHeight: 40).background(Palette.ink, in: buttonShape)
            Button { boughtPrompt = false; model.app.boughtPromptAnswered(saved: false) } label: {
                PoruchIcon(glyph: PoruchIcons.close, size: 16).foregroundStyle(Palette.inkSecondary).frame(width: 40, height: 40)
            }.accessibilityLabel(Copy.close)
        }
        .padding(.leading, Space.lg).padding(.trailing, Space.sm).padding(.vertical, Space.sm)
        .background(Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: Corner.lg, style: .continuous))
        .lifted(Elevation.overlay)
        .padding(.horizontal, Space.md)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// Хто вже шукає компанію на цю афішу. Без імен: організатора видно на сторінці супутника, туди
    /// й веде рядок. «Долучитися» — запит організатору прямо звідси.
    func companionsSection(_ view: DetailScreenState) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader(title: Copy.companions_title)
            VStack(spacing: 0) {
                ForEach(Array(view.companions.enumerated()), id: \.element.id) { index, card in
                    if index > 0 { Divider().overlay(Palette.hairline) }
                    let label = sessionLabel(EventSession(id: card.id, startsAt: card.meetAt, timeZone: card.timeZone, cancelled: false))
                    HStack(spacing: Space.md) {
                        NavigationLink(value: EventRoute(id: card.id)) {
                            VStack(alignment: .leading, spacing: Space.xs) {
                                Text("\(label.day) · \(label.hour)").font(PoruchFont.overline).kerning(1.0).foregroundStyle(Palette.inkTertiary)
                                Text(card.meetNote ?? Copy.venue).font(PoruchFont.cardName).kerning(-0.2).foregroundStyle(Palette.ink)
                                    .multilineTextAlignment(.leading).lineLimit(2)
                                Text(Copy.attendees_short("\(card.attendeeCount)", "\(card.capacity)")).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle(pressedScale: 1))
                        .accessibilityElement(children: .combine)
                        if card.mine { StatusBadge(text: Copy.companion_mine, tone: .brand) }
                        else if card.membership == .approved { StatusBadge(text: Copy.going, tone: .success, glyph: PoruchIcons.check) }
                        else if card.membership == .requested { StatusBadge(text: Copy.request_pending, tone: .accent, glyph: PoruchIcons.queue) }
                        else if card.isFull { StatusBadge(text: Copy.full) }
                        else {
                            SecondaryButton(title: Copy.companion_join, enabled: !view.mutating) {
                                if !actions.joinCompanion(id: card.id, signedIn: view.signedIn) { auth = .join }
                            }.fixedSize()
                        }
                    }
                    .padding(.horizontal, Space.lg).padding(.vertical, Space.md)
                }
            }
            .cardSurface()
        }
    }
}

/// Текст для системного «Поділитися», відкритого не кнопкою, а подією стану.

/// «Тарас кличе тебе» (docs/invites.md): подію відкрили з посилання-запрошення. Над усім іншим на обкладинці — це
/// відповідь на «чому я тут», як рядок причини на квитках стрічки, лише голосом друга.
private struct InviterLine: View {
    let inviter: Inviter
    /// Аватар росте разом із підписом, як у `HostLine`.
    @ScaledMetric(relativeTo: .body) private var avatar: CGFloat = 28
    var body: some View {
        HStack(spacing: Space.sm) {
            Avatar(name: inviter.name, url: inviter.avatarUrl, size: min(avatar, 42))
                .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 1.5))
            Text(Copy.invite_from(inviter.name)).font(PoruchFont.button).foregroundStyle(.white)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
