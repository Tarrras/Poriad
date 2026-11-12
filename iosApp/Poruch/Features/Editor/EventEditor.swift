import SwiftUI
import Shared

/// «Своя зустріч» одним екраном (docs/creation-platform-plan-2026-11.md, етап 2). View малює `EventEditorModel`,
/// валідація й збереження там.
struct EventEditor: View {
    let event: Event?
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var editor: EventEditorModel
    @State private var discardingChanges = false
    @State private var startingOver = false
    /// Щойно опублікована подія: редактор показує «Подію створено» (`AppState.published`).
    @State private var shownPublished: PublishedEvent?
    /// Фокус назви й адреси: відмова «Опублікувати» ставить його туди, де треба набирати, а вибір підказки знімає.
    @FocusState private var titleFocused: Bool
    @FocusState private var addressFocused: Bool
    /// Клавіатура відкрита: панель «Опублікувати» ховається, інакше вдвох вони лишали формі чверть екрана,
    /// а підказки адрес опинялись під кнопкою. «Готово» чи змах униз ховає клавіатуру — і панель повертається.
    @State private var keyboardUp = false

    /// [repeated] — чернетка «Повторити» (`PoruchApp.repeatDraft`): нова подія з полями й медіа іншої.
    init(event: Event?, app: PoruchApp, home: AppState?, repeated: EventDraft? = nil) {
        self.event = event
        _editor = StateObject(wrappedValue: EventEditorModel(app: app, event: event, home: home, repeated: repeated))
    }

    /// Вхід лишається відкритим, поки людина не ввійшла чи поки сервер питає галочку віку (KDoc `publishAfterSignIn`).
    private var waitsForSignIn: Bool {
        guard let state = model.state, state.publishAfterSignIn else { return false }
        return !state.signedIn || state.session.askBirthDate
    }

    /// Одна форма: що, коли, де й скільки людей на видноті, решта під «Ще». Поки подія публікується — накладка з
    /// квитком, що друкується (1.6).
    private var content: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.xxl) {
                        // Квиток друкується згори, поки людина відповідає: той самий, що побачать у «Від людей».
                        DraftTicket(form: editor.form, host: editor.host, taken: editor.taken)
                        // Готовий пост з Threads заповнює все одразу — тож над назвою, а не під «Ще». Лише для нової.
                        if !editor.editing && !editor.repeating { AnnounceCard(editor: editor) }
                        // Чотири питання на одному екрані — хвилина від «+» до посилання.
                        WhatSection(editor: editor, focus: $titleFocused)
                        WhenSection(editor: editor)
                        WhereSection(editor: editor, focus: $addressFocused)
                        PeopleSection(editor: editor)
                        MoreSection(editor: editor)
                        // Правка: застосунок показує прості поля, а склад, серію й оплату онлайн веде кабінет — і не стирає їх.
                        if let url = editor.cabinet { CabinetLine(text: Copy.quick_full_settings, url: url) }
                    }
                    .padding(Space.page)
                }
                .scrollDismissesKeyboard(.interactively)
                // Поле з порушенням — у видиму частину: інакше текст під ним лишався за краєм екрана.
                .onChange(of: editor.jump) { _, _ in
                    guard let field = editor.focus else { return }
                    // Червоний текст під полем VoiceOver не помітить сам.
                    if let text = editor.issue(field) { AccessibilityNotification.Announcement(text).post() }
                    // Поле під «Ще» зʼявляється лише в наступному проході розкладки.
                    DispatchQueue.main.async {
                        if reduceMotion { proxy.scrollTo(field, anchor: .center) }
                        else { withAnimation { proxy.scrollTo(field, anchor: .center) } }
                        // Назва й місце — набирати: фокус туди. Решта (дата, місця, поля під «Ще») — без клавіатури,
                        // щоб вона не закрила поле, до якого щойно привели.
                        titleFocused = field == DraftField.title
                        addressFocused = field == DraftField.address || field == DraftField.location
                    }
                }
                // Підказки адрес з'являються під полем: з клавіатурою вони опинялись під нею. Поле — вгору видимої частини.
                .onChange(of: editor.addressSuggestions.isEmpty) { _, empty in
                    guard !empty, addressFocused, keyboardUp else { return }
                    if reduceMotion { proxy.scrollTo(DraftField.address, anchor: .top) }
                    else { withAnimation { proxy.scrollTo(DraftField.address, anchor: .top) } }
                }
            }
            if !keyboardUp { actions }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardUp = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardUp = false }
        .overlay {
            if publishing {
                PublishingOverlay(upload: model.state?.mediaUpload, stub: categoryStub(editor.form.category))
            }
        }
        .motion(value: publishing)
    }

    var body: some View {
        Group {
            // Опубліковано — «Подію створено» тут же, замість кроків: друга шторка поверх цієї не відкрилась би.
            if let shownPublished {
                PublishedView(published: shownPublished) { finishPublished() }
            } else {
                content
            }
        }
        .background(Palette.canvas)
        // Редактор — аркуш над коренем, тож банер кореня з помилкою публікації лишався під ним.
        .notice(model.state?.notice?.presented) { model.app.clearNotice() }
        .onChange(of: editor.form) { _, _ in editor.scheduleSave() }
        // При згортанні застосунку аркуш не зникає, тож відкладений запис дожимаємо самі.
        .onChange(of: scenePhase) { _, phase in if phase != .active { editor.persist() } }
        .onDisappear {
            editor.persist()
            // «Подію створено» змахнули вниз — те саме, що «Готово».
            if shownPublished != nil { finishPublished(closing: false) }
        }
        // Зміна закінчилась без підтвердженого запису — відмова: форма лишається редагованою й зберігається. Гість, що
        // чекає на вхід, — не відмова: подія опублікується сама, щойно він увійде.
        .onChange(of: model.state?.mutating) { _, mutating in
            guard mutating == false, editor.submitted, model.state?.completedEventId == nil,
                  model.state?.publishAfterSignIn != true else { return }
            let error = (model.state?.notice as? AppNoticeFailed)?.error
            editor.failed(fields: (error as? AppErrorInvalidDraft)?.fields ?? [])
        }
        .onChange(of: model.state?.completedEventId) { _, id in
            guard editor.submitted, let id else { return }
            editor.finish()
            // Нова подія — «Подію створено»; правка — просто закриваємось.
            guard !editor.editing, let published = model.state?.published, published.id == id else { return dismiss() }
            // «Подію опубліковано» каже сам екран; збій файлів (MediaFailed) лишаємо — його треба побачити.
            if model.state?.notice is AppNoticeTold { model.app.clearNotice() }
            withMotion { shownPublished = published }
            // VoiceOver: новий екран, а не та сама форма — і одразу його назва.
            UIAccessibility.post(notification: .screenChanged, argument: Copy.published_title)
        }
        // «Опублікувати» в гостя: вхід поверх редактора з чернеткою під ним. Увійшов — вхід закривається сам, а подія
        // публікується; закрив без входу — публікація скасована, людина лишається тут з тією самою чернеткою.
        .sheet(isPresented: Binding(get: { waitsForSignIn }, set: { if !$0 { model.app.cancelPendingPublish() } })) {
            NavigationStack { AuthView(reason: .create) }
        }
        .onChange(of: model.state?.publishAfterSignIn) { _, waits in
            guard waits == false, model.state?.completedEventId == nil, model.state?.mutating != true else { return }
            editor.failed(fields: [])
        }
        // Під час публікації аркуш не закривається: інакше відповідь сервера нікому було б прийняти,
        // чернетка лишалась би, і наступне «+» публікувало б ту саму подію вдруге.
        .interactiveDismissDisabled(editor.submitted || editor.dirty)
        .confirmationDialog(Copy.editor_discard_title, isPresented: $discardingChanges, titleVisibility: .visible) {
            Button(Copy.editor_discard, role: .destructive) { dismiss() }
            Button(Copy.editor_keep_editing, role: .cancel) {}
        } message: { Text(Copy.editor_discard_explain) }
        .confirmationDialog(Copy.editor_start_over_title, isPresented: $startingOver, titleVisibility: .visible) {
            Button(Copy.editor_delete_draft, role: .destructive) { editor.startOver() }
        } message: { Text(Copy.editor_start_over_explain) }
    }

    /// Подія публікується: накладка з анімацією замість кроків. Гість, що чекає на вхід, ще нічого не публікує.
    private var publishing: Bool {
        editor.submitted && !editor.editing && !waitsForSignIn && model.state?.mutating == true
    }

    /// «Готово» чи змах униз на «Подію створено»: екран зникає (`publish_done {done}`), далі — деталі події. Деталі
    /// відкриває той самий шлях, що й пуш: з будь-якої вкладки, після того як шторка закрилась.
    private func finishPublished(closing: Bool = true) {
        guard let published = shownPublished else { return }
        shownPublished = nil
        model.app.publishDone(action: .done)
        if closing { dismiss() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { PushDelegate.open(eventId: published.id, chat: false) }
    }

    /// Нова подія зберігається в чернетку й закривається одразу; правки наявної — лише після підтвердження.
    private func close() {
        if editor.dirty { discardingChanges = true } else { editor.persist(); dismiss() }
    }

    /// Закрити, назва режиму і «Почати заново».
    private var header: some View {
        HStack(spacing: Space.md) {
            IconPill(glyph: PoruchIcons.close, label: Copy.close, size: 40) { close() }
                .disabled(editor.submitted)
            Text(editor.editing ? Copy.editor_mode_edit : Copy.create_choice_own)
                .font(PoruchFont.brandTitle3).foregroundStyle(Palette.ink).lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if editor.canStartOver {
                Button { startingOver = true } label: {
                    Text(Copy.editor_start_over).font(PoruchFont.button).foregroundStyle(Palette.inkSecondary)
                        .fixedSize()
                }
                .tapTarget()
                .disabled(editor.submitted)
            }
        }
        .frame(height: 56).padding(.horizontal, Space.page).padding(.top, Space.sm)
        // Шапка — хром, як системна навігація: росте до xxLarge, далі напис справа витіснив би назву за край.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    private var actions: some View {
        VStack(spacing: Space.sm) {
            // Подію вже створено, файли йдуть по черзі: людина бачить, чого чекає.
            if let upload = model.state?.mediaUpload {
                Text(Copy.media_uploading("\(upload.current)", "\(upload.total)"))
                    .font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary).monospacedDigit()
            } else if editor.preparing > 0 {
                // Чому «Опублікувати» чекає.
                Text(Copy.media_compressing).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary)
            }
            PrimaryButton(
                title: editor.editing ? Copy.save_changes : Copy.publish,
                loading: model.state?.mutating == true,
                // Не вимкнена, поки форму не заповнено: натискання показує, що саме не так. Чекає лише на стиснення відео.
                enabled: model.state?.mutating != true && editor.preparing == 0
            ) { editor.submit() }
        }
        .padding(Space.page)
        .background(Palette.surface.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 1) }
    }
}

/// Квиток «Від людей», що друкується з форми: незаповнене — сірі смуги, як на порожньому квитку, заповнене проступає
/// текстом. Корінець одразу кольору жанру (його ставить шаблон), на ньому година, день і місця. Смужкою: повний квиток
/// забирав чверть екрана, а тут чотири питання мають стояти поруч. Для VoiceOver він повтор форми, тож прихований.
private struct DraftTicket: View {
    let form: EditorForm
    let host: String?
    let taken: Int

    private var title: String { form.title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var place: String { form.address.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        let parts = draftStubParts(at: form.starts, zone: form.timeZone)
        Ticket(stubColor: categoryStub(form.category), stubLength: 84) {
            VStack(alignment: .leading, spacing: Space.xs) {
                if title.isEmpty { blank(140, height: 10) } else {
                    Text(TitleRules.shared.display(title: title)).font(PoruchFont.brandTitle3).foregroundStyle(Palette.ink).lineLimit(2)
                }
                if let host {
                    HStack(spacing: 6) {
                        Avatar(name: host, url: nil, size: 20)
                        Text(Copy.hosted_by(host)).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary).lineLimit(1)
                    }
                }
                if place.isEmpty { blank(100, height: 6) } else { MetaLine(glyph: PoruchIcons.pin, text: place) }
            }
            .padding(Space.md)
        } stub: {
            VStack(spacing: 2) {
                Text(parts.big).font(PoruchFont.numeralSmall).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                Text(parts.small).font(PoruchFont.overline).kerning(0.6).lineLimit(1).minimumScaleFactor(0.7)
                HStack(spacing: 3) {
                    PoruchIcon(glyph: PoruchIcons.social, size: 12)
                    Text("\(taken)/\(form.capacity)").font(PoruchFont.overline).monospacedDigit()
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Space.xs)
        }
        .motion(value: [title.isEmpty, place.isEmpty])
        .decorative()
    }

    /// Ще не надрукований рядок.
    private func blank(_ width: CGFloat, height: CGFloat) -> some View {
        Capsule().fill(Palette.hairline).frame(width: width, height: height).padding(.vertical, 3)
    }
}

/// Поки подія публікується: квиток друкується в петлі (`publishing.json`), під ним «Завантажуємо N з M» чи «Публікуємо
/// подію…». «Зменшити рух» — надрукований квиток, кадр 0.
private struct PublishingOverlay: View {
    let upload: MediaUpload?
    let stub: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: Space.lg) {
            BrandAnimation(name: "Publishing", still: reduceMotion, stub: stub)
                .frame(width: 300, height: 200)
                .decorative()
            Text(upload.map { Copy.media_uploading("\($0.current)", "\($0.total)") } ?? Copy.publishing_caption)
                .font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary).monospacedDigit()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Непрозоро: крізь накладку просвічував той самий лічильник у нижній панелі редактора.
        .background(Palette.canvas.ignoresSafeArea())
        .accessibilityElement(children: .combine)
        // Модально: поки публікується, «Назад» і поля під накладкою VoiceOver не активує.
        .accessibilityAddTraits([.updatesFrequently, .isModal])
        .transition(.opacity)
    }
}

/// Правило, яке порушує поле, одразу під ним.
private struct FieldIssue: View {
    let text: String?
    var body: some View {
        if let text {
            Text(text).font(PoruchFont.caption).foregroundStyle(Palette.danger)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Питання секції тим самим голосом, що назва на квитку, і відповідь під ним.
private struct QuickSection<Content: View>: View {
    let question: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text(question).font(PoruchFont.brandTitle2).kerning(-0.2).foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            content
        }
    }
}

/// «Що»: назва й шаблони. Шаблон одним тапом ставить назву, жанр (колір корінця), місця й тривалість.
private struct WhatSection: View {
    @ObservedObject var editor: EventEditorModel
    var focus: FocusState<Bool>.Binding
    var body: some View {
        QuickSection(question: Copy.editor_about_title) {
            VStack(alignment: .leading, spacing: Space.sm) {
                LabelledField(label: Copy.title, text: $editor.form.title, placeholder: Copy.quick_title_placeholder, focus: focus)
                    .submitLabel(.done)
                FieldIssue(text: editor.issue(.title))
            }.id(DraftField.title)
            // У правці шаблонів нема: тап переписав би місця, жанр і кінець уже опублікованої події.
            if !editor.editing {
                FlowLayout(spacing: Space.sm) {
                    ForEach(meetupTemplates, id: \.template) { item in
                        Chip(label: item.label, dot: item.template.category, selected: editor.form.meetup == item.template) {
                            editor.pick(item.template, label: item.label)
                        }
                    }
                }
            }
        }
    }
}

/// «Коли»: день одним тапом — сьогодні, завтра, найближчий вихідний чи інша дата — і година поруч.
private struct WhenSection: View {
    @ObservedObject var editor: EventEditorModel
    /// Шторка: false — день, true — година.
    @State private var picking: Bool?

    private func label(_ day: QuickDay) -> String {
        switch day.kind {
        case .today: Copy.today
        case .tomorrow: Copy.tomorrow
        default: day.sunday ? Copy.quick_sunday : Copy.quick_saturday
        }
    }

    var body: some View {
        let picked = editor.pickedDay
        let parts = fieldDateParts(editor.form.starts, zone: editor.form.timeZone)
        QuickSection(question: Copy.editor_schedule_title) {
            FlowLayout(spacing: Space.sm) {
                ForEach(editor.days, id: \.kind) { day in
                    Chip(label: label(day), selected: picked == day.kind) { editor.pick(day) }
                }
                // Інша дата — чип із самим днем, коли його обрано: «Пт, 20 лист.».
                Chip(
                    label: picked == nil ? parts.day : Copy.quick_other_date, glyph: PoruchIcons.calendar,
                    trailingGlyph: PoruchIcons.chevronDown, selected: picked == nil
                ) { picking = false }
                Chip(label: parts.time, glyph: PoruchIcons.clock, trailingGlyph: PoruchIcons.chevronDown, selected: false) { picking = true }
                    .accessibilityLabel("\(Copy.start_time): \(parts.time)")
            }
            FieldIssue(text: editor.issue(.startsAt))
        }
        .id(DraftField.startsAt)
        .sheet(isPresented: Binding(get: { picking != nil }, set: { if !$0 { picking = nil } })) {
            // Шторка міняє форму одразу: квиток згори передруковує корінець, поки крутиш барабан.
            PickerSheet(
                title: picking == true ? Copy.start_time : Copy.start_date, time: picking == true,
                value: Binding(get: { editor.form.starts }, set: { editor.moveStart(to: $0) }),
                minimum: Date(), zone: editor.form.timeZone
            )
        }
    }
}

/// «Є готовий анонс?» над назвою: організатор з Threads уже написав пост, тож поля заповнює він (`parse-announcement`).
/// Один рядок із системною «Вставити»: вставили — одразу заповнюємо, поля для набору нема (рішення власника 02.11).
/// Після відповіді — рядок «Заповнили з анонсу: …» з «Інший текст».
private struct AnnounceCard: View {
    @ObservedObject var editor: EventEditorModel
    @Environment(\.dynamicTypeSize) private var typeSize
    private var limit: Int { Int(AnnouncementRules.shared.TEXT_MAX) }

    var body: some View {
        Group {
            if let result = editor.announced { collapsed(result) } else { expanded }
        }
        .padding(Space.lg).frame(maxWidth: .infinity, alignment: .leading)
        // Тоном, а не білою карткою: біле поле тексту на білій картці зникало.
        .background(Palette.brandContainer, in: RoundedRectangle(cornerRadius: Corner.lg, style: .continuous))
        .motion(value: editor.announced)
    }

    private var expanded: some View {
        // На великому шрифті «Вставити» — під текстом: поруч напис стискався б до слова в рядку.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.md)) : AnyLayout(HStackLayout(spacing: Space.md))
        return layout {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(Copy.announce_title).font(PoruchFont.cardName).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
                Text(Copy.announce_subtitle).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if editor.announcing {
                HStack(spacing: Space.sm) {
                    ProgressView()
                    Text(Copy.announce_filling).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary)
                }
                .accessibilityElement(children: .combine)
            } else {
                // Системна «Вставити»: бере з буфера без питання про доступ, і одразу заповнює.
                PasteButton(payloadType: String.self) { strings in
                    guard let text = strings.first else { return }
                    Task { @MainActor in
                        editor.announceText = String(text.prefix(limit))
                        editor.fillFromAnnouncement()
                    }
                }
                .labelStyle(.titleAndIcon).buttonBorderShape(.capsule).tint(Palette.ink)
            }
        }
    }

    private func collapsed(_ result: AnnounceResult) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                PoruchIcon(glyph: result.failed ? PoruchIcons.alert : PoruchIcons.checkCircle, size: 18)
                    .foregroundStyle(result.failed ? Palette.danger : Palette.success)
                Text(result.text).font(PoruchFont.subhead).foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Button(Copy.announce_other) { editor.reopenAnnouncement() }
                .font(PoruchFont.button).foregroundStyle(Palette.inkSecondary).tapTarget()
        }
    }
}

/// «Де»: адреса з підказками або точка на мапі. Мапа — лише підтвердження вибраного, тож з'являється з крапкою.
private struct WhereSection: View {
    @ObservedObject var editor: EventEditorModel
    var focus: FocusState<Bool>.Binding
    @State private var mapLatitude: Double
    @State private var mapLongitude: Double
    @State private var picking = false

    /// Центр мапи задаємо тут, а не в `onAppear`, інакше перший кадр малюється в (0, 0).
    init(editor: EventEditorModel, focus: FocusState<Bool>.Binding) {
        _editor = ObservedObject(wrappedValue: editor)
        self.focus = focus
        _mapLatitude = State(initialValue: editor.form.latitude)
        _mapLongitude = State(initialValue: editor.form.longitude)
    }
    private var form: Binding<EditorForm> { $editor.form }
    /// Крапка рядком: кортеж не `Equatable`, а `onSettled` порівнює значення.
    private var audienceKey: String { editor.form.point.map { "\($0.latitude),\($0.longitude)" } ?? "" }
    var body: some View {
        QuickSection(question: Copy.editor_place_title) { fields }
    }

    @ViewBuilder private var fields: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            LabelledField(label: Copy.address, text: form.address, placeholder: Copy.address_placeholder, focus: focus)
            FieldIssue(text: editor.issue(.address))
        }.id(DraftField.address)
        // Підказки одразу під полем, як продовження набору.
        if !editor.addressSuggestions.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(editor.addressSuggestions.enumerated()), id: \.offset) { index, place in
                    if index > 0 { Divider().overlay(Palette.hairline).padding(.horizontal, Space.lg) }
                    // Адресу обрано — клавіатура більше не потрібна: вона закривала мапу з точкою й «Опублікувати».
                    Button { focus.wrappedValue = false; editor.pick(place) } label: {
                        HStack(spacing: Space.md) {
                            PoruchIcon(glyph: PoruchIcons.pin, size: 18).foregroundStyle(Palette.inkSecondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.label).font(PoruchFont.bodyText).foregroundStyle(Palette.ink)
                                if !place.detail.isEmpty {
                                    Text(place.detail).font(PoruchFont.caption)
                                        .foregroundStyle(Palette.inkTertiary).lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(Space.lg).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
        // Мапа лише показує вибране: жести на такій висоті коштували б точності.
        if editor.pointChosen {
            EventMap(
                events: [], latitude: mapLatitude, longitude: mapLongitude,
                centerZoom: MapZoom.street,
                chosenPoint: editor.form.point,
                interactive: false,
                selected: { _ in },
                moved: { _ in }
            )
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: Corner.md, style: .continuous))
        }
        // Один рядок про місце: що зробити, що вже є, або — після «Опублікувати» — чого бракує, на тому ж місці.
        // Координат не показуємо: людина знає адресу, а не широту.
        if let issue = editor.issue(.location) {
            FieldIssue(text: issue).id(DraftField.location)
        } else {
            MetaLine(
                glyph: editor.pointChosen ? PoruchIcons.checkCircle : PoruchIcons.pin,
                text: editor.pointChosen ? Copy.address_point_set : Copy.address_or_map
            )
        }
        // Тихо, як рядок про крапку: число людей поруч — привід, а не умова публікації. Прихована — нікому не кажемо.
        if let audience = editor.audience, editor.form.linkOnly != true {
            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                PoruchIcon(glyph: PoruchIcons.bell, size: 15).foregroundStyle(Palette.inkTertiary)
                Text(Copy.editor_audience(audience)).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
        SecondaryButton(title: editor.pointChosen ? Copy.change_point : Copy.choose_point) {
            picking = true
        }
        .frame(maxWidth: .infinity)
        .task { editor.countAudience() }
        .onSettled(audienceKey, after: .milliseconds(400)) { _ in editor.countAudience() }
        // Слухаємо лічильник, а не координати: від панорами вони теж міняються.
        .onChange(of: editor.placedAt) { _, _ in
            mapLatitude = editor.form.latitude
            mapLongitude = editor.form.longitude
        }
        .onSettled(editor.form.address, after: .milliseconds(350)) { editor.suggestAddresses($0) }
        .fullScreenCover(isPresented: $picking) {
            PointPicker(
                editor: editor,
                start: editor.form.point ?? (mapLatitude, mapLongitude),
                zoom: editor.pointChosen ? MapZoom.street : MapZoom.city
            ) { latitude, longitude in
                mapLatitude = latitude
                mapLongitude = longitude
            }
        }
        // Тут, а не в «Ще»: про приватність адреси думають, коли її вводять («Настолки вдома»).
        Toggle(isOn: Binding(get: { editor.form.linkOnly == true }, set: { editor.form.linkOnly = $0 })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Copy.link_only_label).font(PoruchFont.bodyText).foregroundStyle(Palette.ink)
                Text(Copy.link_only_hint).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.tint(Palette.brand)
        .padding(Space.lg).cardSurface()
    }
}

/// «Скільки людей»: число великими цифрами, як на корінці, і «−» / «+» для дрібних поправок. Понад 30 — підказка про кабінет.
private struct PeopleSection: View {
    @ObservedObject var editor: EventEditorModel
    var body: some View {
        QuickSection(question: Copy.quick_people) {
            HStack(spacing: Space.md) {
                ZoomButton(glyph: PoruchIcons.minus, label: Copy.quick_seats_less) { step(-1) }
                TextField(Copy.capacity, text: Binding(
                    // Стерте поле лишається порожнім, а не стрибає в «0» під курсором.
                    get: { editor.form.capacity == 0 ? "" : "\(editor.form.capacity)" },
                    set: { editor.form.capacity = Int(String($0.filter(\.isNumber).prefix(5))) ?? 0 }
                ))
                .font(PoruchFont.numeral).monospacedDigit().multilineTextAlignment(.center)
                .foregroundStyle(Palette.ink).tint(Palette.ink).keyboardType(.numberPad)
                .frame(width: 112).padding(.vertical, Space.md)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: Corner.sm, style: .continuous))
                ZoomButton(glyph: PoruchIcons.plus, label: Copy.quick_seats_more) { step(1) }
            }
            FieldIssue(text: editor.issue(.capacity))
            // Підказка, не заборона: великій події зручніше в кабінеті, але й тут її можна опублікувати.
            if QuickEvent.shared.isLarge(capacity: Int32(clamping: editor.form.capacity)), let url = URL(string: LegalLinks.shared.CABINET) {
                CabinetLine(text: Copy.quick_large_hint, url: url)
            }
        }
        .id(DraftField.capacity)
    }

    private func step(_ delta: Int) {
        editor.form.capacity = min(max(editor.form.capacity + delta, capacityRange.lowerBound), capacityRange.upperBound)
    }
}

/// Тихий рядок із посиланням на кабінет: підказка великої події й «Повні налаштування» у правці.
private struct CabinetLine: View {
    let text: String
    let url: URL
    @Environment(\.openURL) private var openURL
    var body: some View {
        Button { openURL(url) } label: {
            HStack(spacing: Space.md) {
                Text(text).font(PoruchFont.subhead).foregroundStyle(Palette.ink).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                PoruchIcon(glyph: PoruchIcons.arrowRight, size: 18).foregroundStyle(Palette.inkSecondary)
            }
            .padding(.horizontal, Space.lg).padding(.vertical, Space.md)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Palette.surfaceMuted, in: RoundedRectangle(cornerRadius: Corner.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint(Copy.quick_open_cabinet)
    }
}

/// «Ще» — згорнуто: опис, фото, «За підтвердженням», чат і вхід, а під ними те, що за планом лишиться тільки сайту
/// (кілька фото й відео, вік, коли платять) — поки тут, щоб правка події з сайту нічого не губила.
private struct MoreSection: View {
    @ObservedObject var editor: EventEditorModel
    private var form: Binding<EditorForm> { $editor.form }
    private var issues: [DraftField: String] { editor.issueTexts }
    private var descriptionRange: KotlinIntRange { EventRules.shared.descriptionLength }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            Button { withMotion { editor.toggleMore() } } label: {
                HStack(spacing: Space.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Copy.quick_more).font(PoruchFont.cardName).foregroundStyle(Palette.ink)
                        Text(Copy.quick_more_hint).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary)
                    }
                    Spacer(minLength: 0)
                    PoruchIcon(glyph: editor.more ? PoruchIcons.chevronUp : PoruchIcons.chevronDown, size: 20)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .padding(Space.lg).frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface(radius: Corner.md)
            }
            .buttonStyle(.plain)
            .accessibilityValue(editor.more ? Copy.expanded : Copy.collapsed)
            if editor.more { fields }
        }
    }

    @ViewBuilder private var fields: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            LabelledField(
                label: Copy.description, text: form.description,
                placeholder: Copy.description_placeholder,
                hint: editor.form.descriptionLength == 0 ? Copy.quick_about_hint(editor.form.about)
                    : Copy.description_hint("\(descriptionRange.first)", "\(editor.form.descriptionLength)", "\(descriptionRange.last)"),
                multiline: true
            )
            FieldIssue(text: issues[.description_])
        }.id(DraftField.description_)
        MediaSection(editor: editor)
        VStack(alignment: .leading, spacing: Space.md) {
            Toggle(isOn: form.approvalRequired) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Copy.approval_label).font(PoruchFont.bodyText).foregroundStyle(Palette.ink)
                    Text(Copy.approval_hint)
                        .font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary)
                }
            }.tint(Palette.brand)
            .padding(Space.lg).cardSurface()
            // Чат — єдиний канал до учасників. Лише https: решту відкидає і чернетка, і сервер.
            LabelledField(
                label: Copy.contact_label,
                text: Binding(get: { editor.form.contactUrl ?? "" }, set: { editor.form.contactUrl = String($0.prefix(Int(ContactRules.shared.MAX_URL_LENGTH))) }),
                placeholder: "https://t.me/…",
                hint: Copy.contact_editor_hint
            )
            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
            .id(DraftField.contactUrl)
            FieldIssue(text: issues[.contactUrl])
        }
        EntryFields(form: form, issues: issues, payOnline: editor.payOnline)
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(Copy.category_single.uppercased()).font(PoruchFont.overline).kerning(1.0).foregroundStyle(Palette.inkTertiary)
            // Ті самі плитки, що в шторці категорій пошуку: жанр обирають однаково скрізь.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: Space.sm)], spacing: Space.md) {
                ForEach(categories, id: \.0) { category in
                    CategoryTile(category: category.0, selected: editor.form.category == category.0) {
                        editor.form.category = category.0
                    }
                }
            }
            FieldIssue(text: issues[.category])
        }.id(DraftField.category)
        // Кінець ставить шаблон (тривалість) і їде за початком; тут — коли треба інакше.
        ScheduleFields(starts: form.starts, ends: form.ends, zone: editor.form.timeZone, endOnly: true).id(DraftField.endsAt)
        FieldIssue(text: issues[.endsAt])
        TimeZoneNote(zone: editor.form.timeZone, city: editor.form.city, at: editor.form.starts).id(DraftField.timeZone)
        FieldIssue(text: issues[.timeZone])
        AgeFields(form: form, issue: issues[.ageLimits])
        // Місто їде за адресою з підказки чи крапкою; поле — коли геокодер помилився.
        LabelledField(label: Copy.city, text: form.city, placeholder: Copy.city_example)
            .textInputAutocapitalization(.words)
    }
}

/// Вхід: спершу безкоштовно чи платно (власник 05.11). Платно — ціна й коли платять; безкоштовно прибирає обидва.
private struct EntryFields: View {
    @Binding var form: EditorForm
    /// Тексти під полями значенням, а не замиканням: замикання SwiftUI не порівнює.
    let issues: [DraftField: String]
    /// Правка події з оплатою онлайн: підказка під ціною — про неї, а не «на місці».
    var payOnline = false
    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(Copy.entry_label.uppercased()).font(PoruchFont.overline).kerning(1.0).foregroundStyle(Palette.inkTertiary)
            SegmentedPill(items: [Copy.entry_free, Copy.entry_paid], selection: form.isPaid ? 1 : 0) { index in
                if index == 1 {
                    form.paid = true
                } else {
                    form.paid = false; form.price = nil; form.prepay = nil
                }
            }
        }
        // Онлайн застосунок не вмикає (лише кабінет на сайті), а коли платять — обирає.
        if form.isPaid {
            VStack(alignment: .leading, spacing: Space.sm) {
                LabelledField(
                    label: Copy.price_label,
                    text: Binding(
                        get: { form.price.map(String.init) ?? "" },
                        set: { form.price = Int(String($0.filter(\.isNumber).prefix(6))) }
                    ),
                    placeholder: Copy.price_placeholder,
                    hint: payOnline ? Copy.price_hint_online : nil
                )
                .keyboardType(.numberPad)
                FieldIssue(text: issues[.price])
            }.id(DraftField.price)
        }
        // Коли платять: людина бачить це під ціною й на панелі. Онлайн-подію змінюють у кабінеті.
        if form.isPaid && !payOnline {
            VStack(alignment: .leading, spacing: Space.sm) {
                Text(Copy.pay_when_label.uppercased()).font(PoruchFont.overline).kerning(1.0).foregroundStyle(Palette.inkTertiary)
                SegmentedPill(items: [Copy.pay_when_meeting, Copy.pay_when_prepay], selection: form.prepay == true ? 1 : 0) {
                    form.prepay = $0 == 1
                }
                Text(form.prepay == true ? Copy.pay_when_prepay_hint : Copy.pay_when_meeting_hint)
                    .font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Вікові межі: за планом — лише сайт, поки лишаються під «Ще».
private struct AgeFields: View {
    @Binding var form: EditorForm
    let issue: String?
    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            VStack(alignment: .leading, spacing: Space.lg) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Stepper("\(Copy.age_from): \(form.minAge)", value: $form.minAge, in: ageRange)
                    Text(Copy.age_limit_hint("\(Int(SafetyRules.shared.MIN_SIGNUP_AGE))"))
                        .font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary)
                }
                Toggle(Copy.age_max_toggle, isOn: Binding(
                    get: { form.maxAge != nil },
                    set: { form.maxAge = $0 ? max(form.minAge, form.minAge + 7) : nil }
                )).tint(Palette.brand)
                if let maximum = form.maxAge {
                    Stepper("\(Copy.age_to): \(maximum)", value: Binding(
                        get: { maximum }, set: { form.maxAge = $0 }
                    ), in: form.minAge...Int(SafetyRules.shared.MAX_AGE_LIMIT))
                }
            }
            .font(PoruchFont.bodyText).foregroundStyle(Palette.ink)
            .padding(Space.lg).cardSurface()
            .id(DraftField.ageLimits)
            FieldIssue(text: issue)
        }
    }
}

/// Нижче за мінімум платформи організатор поставити не може.
private var ageRange: ClosedRange<Int> { Int(SafetyRules.shared.MIN_SIGNUP_AGE)...100 }

/// Той самий діапазон, що в CHECK на сервері.
private var capacityRange: ClosedRange<Int> {
    Int(EventRules.shared.capacity.first)...Int(EventRules.shared.capacity.last)
}

/// Повноекранна мапа з ціллю в центрі: рухається світ під нею, крапку не затуляє палець.
private struct PointPicker: View {
    @ObservedObject var editor: EventEditorModel
    let start: (latitude: Double, longitude: Double)
    let zoom: Double
    let onDone: (Double, Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller = MapController()
    @State private var center: (latitude: Double, longitude: Double)

    init(
        editor: EventEditorModel,
        start: (latitude: Double, longitude: Double),
        zoom: Double,
        onDone: @escaping (Double, Double) -> Void
    ) {
        _editor = ObservedObject(wrappedValue: editor)
        self.start = start
        self.zoom = zoom
        self.onDone = onDone
        _center = State(initialValue: start)
    }

    var body: some View {
        ZStack {
            EventMap(
                events: [], latitude: start.latitude, longitude: start.longitude,
                centerZoom: zoom,
                selected: { _ in },
                moved: { _ in },
                // Мапа повідомляє про зупинку, а не про кожен кадр.
                centerChanged: { latitude, longitude in
                    center = (latitude, longitude)
                    editor.aim(at: latitude, longitude: longitude)
                },
                controller: controller
            )
            .ignoresSafeArea()
            // Ціль не приймає дотиків: мапа під нею має тягтися.
            PoruchIcon(glyph: PoruchIcons.pin, size: 36)
                .foregroundStyle(Palette.brand)
                .offset(y: -18)
                .allowsHitTesting(false)
            VStack(spacing: 0) {
                // Модальний екран: «Скасувати» справа, як у системних аркушах, а не стрілка «назад».
                PageHeader(title: Copy.choose_point_title) {
                    Button(Copy.cancel) { dismiss() }
                        .font(PoruchFont.button).foregroundStyle(Palette.inkSecondary).tapTarget()
                }
                    .background(Palette.canvas)
                Spacer(minLength: 0)
                HStack {
                    Spacer(minLength: 0)
                    VStack(spacing: Space.sm) {
                        ZoomButton(glyph: PoruchIcons.plus, label: Copy.zoom_in) { controller.zoomIn() }
                        ZoomButton(glyph: PoruchIcons.minus, label: Copy.zoom_out) { controller.zoomOut() }
                    }
                }
                .padding(Space.lg)
                Spacer(minLength: 0)
                VStack(spacing: Space.md) {
                    // Адреса тут головна, тож і виглядає як головна.
                    HStack(spacing: Space.md) {
                        PoruchIcon(glyph: PoruchIcons.pin, size: 18).foregroundStyle(Palette.inkSecondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(editor.aimAddress.isEmpty ? Copy.point_searching : editor.aimAddress)
                                .font(PoruchFont.bodyText)
                                .foregroundStyle(editor.aimAddress.isEmpty ? Palette.inkTertiary : Palette.ink)
                                .lineLimit(2)
                            Text(Copy.choose_point_hint)
                                .font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary)
                        }
                        Spacer(minLength: 0)
                    }
                    PrimaryButton(title: Copy.apply) {
                        editor.confirmAim(latitude: center.latitude, longitude: center.longitude)
                        onDone(center.latitude, center.longitude)
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(Space.page)
                .background(Palette.surface)
            }
        }
        .onAppear { editor.aim(at: start.latitude, longitude: start.longitude) }
    }
}

/// Кругла кнопка масштабу поверх мапи.
struct ZoomButton: View {
    let glyph: PoruchGlyph
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PoruchIcon(glyph: glyph, size: 20)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 44, height: 44)
                .background(Palette.surface, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// ---- «+» питає одне

/// «+» питає одне (docs/creation-platform-plan-2026-11.md, етап 2): покликати компанію на подію з афіші чи зібрати свою
/// зустріч. Два квитки: надрукований, з корінцем жанру — афіша; порожній з олівцем — свою друкуєш сам.
private struct CreateChoiceSheet: View {
    /// true — своя зустріч, false — афіша.
    let choose: (Bool) -> Void
    @State private var height: CGFloat = 320

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text(Copy.create_choice_title).font(PoruchFont.brandTitle2).kerning(-0.2).foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader).padding(.bottom, Space.xs)
            // Своя зустріч — першою: створення під «+» (принцип 2), а на афішу йдуть з самої афіші.
            CreateEventCard(title: Copy.create_choice_own, subtitle: Copy.create_choice_own_hint) { choose(true) }
            Button { choose(false) } label: {
                Ticket(stubColor: categoryStub(.music), stubLength: 64, surface: Palette.surface) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Copy.create_choice_afisha).font(PoruchFont.brandTitle3).foregroundStyle(Palette.ink)
                        Text(Copy.create_choice_afisha_hint).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary)
                            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, Space.lg).padding(.vertical, Space.md)
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                } stub: {
                    PoruchIcon(glyph: PoruchIcons.ticket, size: 22).foregroundStyle(.white)
                }
            }
            .buttonStyle(PressableStyle())
        }
        .padding(.horizontal, Space.page).padding(.top, Space.xl).padding(.bottom, Space.lg)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.canvas)
    }
}

extension View {
    /// Шторка вибору після «Створити». Відповідь — коли шторка вже закрилась: редактор — теж шторка, і дві разом
    /// SwiftUI не покаже. [own] відкриває редактор, [afisha] веде на мапу, де в події є «Хочу піти з компанією».
    func createChoice(isPresented: Binding<Bool>, app: PoruchApp, own: @escaping () -> Void, afisha: @escaping () -> Void) -> some View {
        modifier(CreateChoice(isPresented: isPresented, app: app, own: own, afisha: afisha))
    }
}

private struct CreateChoice: ViewModifier {
    @Binding var isPresented: Bool
    let app: PoruchApp
    let own: () -> Void
    let afisha: () -> Void
    @State private var picked: Bool?

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented, onDismiss: {
            defer { picked = nil }
            switch picked {
            case true?: own()
            case false?: app.createFromAfisha(); afisha()
            default: break
            }
        }) {
            CreateChoiceSheet { picked = $0; isPresented = false }
        }
    }
}
