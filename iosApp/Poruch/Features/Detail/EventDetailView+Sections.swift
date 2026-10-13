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
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: Space.md) {
                    badges(event, view)
                    VStack(alignment: .leading, spacing: Space.sm) {
                        // Відлік лише для сьогоднішнього, як на картці плану головної.
                        Text(heroOverline(event)).font(PoruchFont.overline).kerning(1.0).foregroundStyle(Palette.accentOnPhoto)
                            .lineLimit(2)
                        Text(event.displayTitle).font(PoruchFont.serifDisplay).kerning(-0.5).foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, Space.page).padding(.bottom, Space.xl)
                // Текст їде зі стрічкою, а смуга статусу з'являється лише з аркушем: назва гасне, поки не дійшла до годинника.
                .opacity(heroTextOpacity(cancelled: view.cancelled))
            }
            .overlay(alignment: .top) {
                HStack(spacing: Space.sm) {
                    ScrimButton(glyph: PoruchIcons.chevronLeft, label: Copy.back) { dismiss() }
                    Spacer()
                    ScrimButton(
                        glyph: view.saved ? PoruchIcons.bookmarkFilled : PoruchIcons.bookmark,
                        label: view.saved ? Copy.unsave : Copy.save
                    ) { if !actions.toggleSaved(event, signedIn: view.signedIn) { auth = true } }
                }.padding(Space.page)
            }
    }

    func heroTextOpacity(cancelled: Bool) -> Double {
        let scrolled = min(max(1 - (-offset - heroTextFadeFrom) / heroTextFade, 0), 1)
        return (cancelled ? 0.7 : 1) * scrolled
    }

    func heroOverline(_ event: Event) -> String {
        parseEventDate(event.startsAt).map(Calendar.current.isDateInToday) == true ? countdownOverline(event) : cardOverline(event)
    }

    /// Категорія і стан: на обкладинці, тому в стилі «на фото».
    func badges(_ event: Event, _ view: DetailScreenState) -> some View {
        HStack(spacing: Space.sm) {
            StatusBadge(text: categoryName(event.category), tone: .brand, onPhoto: true)
            if view.cancelled { StatusBadge(text: Copy.cancelled_short, tone: .danger, onPhoto: true) }
            // Афіша завжди підписана джерелом: атрибуція обов'язкова.
            else if let listing = view.listing {
                StatusBadge(text: listing.isWithdrawn ? Copy.listing_withdrawn : Copy.listing_badge("\(listing.sourceName)"), tone: .neutral, onPhoto: true)
            }
            else if view.organizer { StatusBadge(text: Copy.you_organize, tone: .neutral, onPhoto: true) }
            // Після кінця лишається лише факт участі: черга й місця вже нічого не значать.
            else if view.ended { if view.room?.joined == true { StatusBadge(text: Copy.went, tone: .neutral, glyph: PoruchIcons.check, onPhoto: true) } }
            else if view.room?.joined == true { StatusBadge(text: Copy.going, tone: .success, glyph: PoruchIcons.check, onPhoto: true) }
            else if view.waitlisted { StatusBadge(text: Copy.in_queue, tone: .accent, glyph: PoruchIcons.queue, onPhoto: true) }
            else if view.room?.awaitingApproval == true { StatusBadge(text: Copy.request_pending, tone: .accent, glyph: PoruchIcons.queue, onPhoto: true) }
            else if eventScarce(event), let room = view.room { StatusBadge(text: Copy.seats_left("\(room.seatsLeft)"), tone: .accent, onPhoto: true) }
        }
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
        if let listing = event.listing {
            cells.append((Copy.listing_source_label, listing.sourceName))
            cells.append((Copy.listing_price_label, listingPrice(listing)))
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
        Button { if view.signedIn { openPerson(userId) } else { auth = true } } label: {
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
            ShareLink(item: SystemActions.shareText(for: event)) {
                RoundAction(title: Copy.share) { PoruchIcon(glyph: PoruchIcons.share, size: 20) }
            }.buttonStyle(PressableStyle())
            .simultaneousGesture(TapGesture().onEnded { model.app.eventShared() })
            Button { screen.handedOff = true; model.app.selectEvent(id: screen.cardID()); openMap() } label: {
                RoundAction(title: Copy.on_map) { PoruchIcon(glyph: PoruchIcons.map, size: 20) }
            }.buttonStyle(PressableStyle())
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
                guard view.signedIn else { auth = true; return }
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
        VStack(alignment: .leading, spacing: Space.sm) {
            Button { withMotion { showOthersHere.toggle() } } label: {
                HStack(spacing: Space.sm) {
                    Text(placeName.map { Copy.others_here_at("\($0)") } ?? Copy.others_here).font(PoruchFont.serifTitle2).kerning(-0.2)
                        .foregroundStyle(Palette.ink).multilineTextAlignment(.leading)
                    Spacer(minLength: Space.sm)
                    Text("\(othersHere.count)").font(PoruchFont.label).foregroundStyle(Palette.inkSecondary).monospacedDigit()
                    PoruchIcon(glyph: PoruchIcons.chevronDown, size: 16).foregroundStyle(Palette.inkTertiary)
                        .rotationEffect(.degrees(showOthersHere ? 180 : 0))
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
                                Text(TitleRules.shared.display(title: other.title)).font(PoruchFont.serifTitle3).kerning(-0.1).foregroundStyle(Palette.ink)
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
                    .background(Palette.brandContainer, in: Capsule())
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
                    Button(Copy.decline) { model.app.declineMember(eventId: event.id, userId: person.userId) }
                        .font(PoruchFont.button).foregroundStyle(Palette.inkSecondary).lineLimit(1).fixedSize()
                    Button(Copy.approve) { model.app.approveMember(eventId: event.id, userId: person.userId) }
                        .font(PoruchFont.button).foregroundStyle(Palette.onBrand).lineLimit(1).fixedSize()
                        .padding(.horizontal, Space.lg).frame(height: 40)
                        .background(Palette.brand, in: Capsule())
                }.padding(Space.lg).frame(maxWidth: .infinity, alignment: .leading).cardSurface()
            }
        }
    }

    /// Скарга й блокування внизу сторінки, не в меню: важка скарга — неподана скарга.
    func safetyActions(_ view: DetailScreenState) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Divider().overlay(Palette.hairline)
            HStack(spacing: Space.lg) {
                Button(Copy.chat_report) { if view.signedIn { reporting = .event } else { auth = true } }
                // Блокувати нема кого без людини; скарга на афішу лишається.
                if view.event?.organizerId != nil {
                    Button(Copy.block_user) { if view.signedIn { blocking = true } else { auth = true } }
                }
                Spacer(minLength: 0)
            }.font(PoruchFont.button).foregroundStyle(Palette.inkSecondary)
        }
    }

    func organizerActions(_ view: DetailScreenState) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Divider().overlay(Palette.hairline)
            // Час, місце й місткість супутника тримає сервер: лишається скасувати.
            if view.companionOf == nil {
                PhotosPicker(selection: $photo, matching: .images) {
                    Label(Copy.add_photo, systemImage: "camera")
                        .font(PoruchFont.subhead.weight(.semibold)).foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity).frame(minHeight: 52)
                        .background(Palette.brandContainer, in: Capsule())
                }.disabled(view.mutating)
            }
            if let error = actions.photoError {
                Text(error).font(PoruchFont.caption).foregroundStyle(Palette.danger)
            }
            HStack(spacing: Space.md) {
                if view.companionOf == nil { SecondaryButton(title: Copy.edit, glyph: PoruchIcons.edit) { editing = true } }
                SecondaryButton(title: Copy.delete_account_cancel, glyph: PoruchIcons.close, tone: Palette.danger) { cancelling = true }
            }
        }
    }

    func stickyBar(_ event: Event, _ view: DetailScreenState) -> some View {
        VStack(spacing: Space.md) {
            HStack(spacing: Space.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(eventOverline(event)).font(PoruchFont.overline).kerning(1.2)
                        .foregroundStyle(Palette.inkTertiary).lineLimit(1)
                    Text(view.seatsSummary).font(PoruchFont.subhead)
                        .foregroundStyle(view.cancelled ? Palette.danger : Palette.inkSecondary).lineLimit(2)
                }
                Spacer(minLength: 0)
                // Кнопки може не бути: у знятої афіші й афіші без посилання нема куди вести.
                if view.action != .none {
                    primaryAction(event, view).fixedSize(horizontal: true, vertical: false)
                }
            }
            // «Шукаю компанію» під квитком на всю ширину: поруч із ціною й квитком не влазить.
            if view.canSeekCompany {
                SecondaryButton(title: Copy.companion_seek, glyph: PoruchIcons.social, enabled: !view.mutating) {
                    if view.signedIn { seekingCompany = true } else { auth = true }
                }
            }
        }
        // Плаває над сторінкою: дія під пальцем, а не смуга на всю ширину. Суцільна картка, а не скло:
        // скло над світлим полотном зливалось із ним, а «Шукаю компанію» всередині — зі склом.
        .padding(.horizontal, Space.lg).padding(.vertical, Space.md)
        .cardSurface(radius: Corner.xl, elevation: Elevation.overlay)
        .padding(.horizontal, Space.md)
    }
}

extension EventDetailView {
    func primaryAction(_ event: Event, _ view: DetailScreenState) -> some View {
        PrimaryButton(
            title: view.action.title,
            tone: view.action == .leave ? Palette.success : view.action == .leaveWaitlist ? Palette.accent : nil,
            loading: view.mutating,
            enabled: view.action.isEnabled && !view.mutating
        ) {
            if !actions.perform(view.action, on: event, signedIn: view.signedIn) { auth = true }
        }
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
                                if !actions.joinCompanion(id: card.id, signedIn: view.signedIn) { auth = true }
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
