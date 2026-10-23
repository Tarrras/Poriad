import SwiftUI
import Shared

/// Публікація в три кроки: що, де, коли. View малює `EventEditorModel`, валідація й збереження там.
struct EventEditor: View {
    let event: Event?
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @StateObject private var editor: EventEditorModel
    @State private var discardingChanges = false
    @State private var startingOver = false

    init(event: Event?, app: PoruchApp, home: AppState?) {
        self.event = event
        _editor = StateObject(wrappedValue: EventEditorModel(app: app, event: event, home: home))
    }

    var body: some View {
        VStack(spacing: 0) {
            wizardHeader
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.lg) {
                        // Квиток друкується згори, поки людина відповідає: той самий, що побачать у «Від людей».
                        // На «Де» і «Коли» — смужкою: повний квиток забирав чверть екрана, і мапа з датами йшли за згин.
                        DraftTicket(
                            form: editor.form, host: editor.host, taken: editor.taken,
                            timed: editor.step.rawValue >= EditorStep.schedule.rawValue || editor.editing,
                            compact: editor.step == .place || editor.step == .schedule
                        )
                        // Кожен крок — одне питання великим заголовком, як в онбордингу.
                        VStack(alignment: .leading, spacing: Space.xs) {
                            // Номер кроку словами: смужки згори кажуть «скільки», а не «котрий». Без капсу: «КРОК 1 З 4»
                            // у цьому шрифті читалось як «1 3 4».
                            Text(stepLabel(editor.step)).font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary).decorative()
                            Text(editor.step.headline).font(PoruchFont.brandDisplay).kerning(-0.5).foregroundStyle(Palette.ink)
                                .accessibilityAddTraits(.isHeader)
                            Text(editor.step.hint).font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary)
                        }.padding(.bottom, Space.xs)
                        switch editor.step {
                        case .about: AboutStep(form: $editor.form, issues: editor.issueTexts)
                        case .place: PlaceStep(editor: editor)
                        case .schedule: ScheduleStep(form: $editor.form, issues: editor.issueTexts)
                        case .people: PeopleStep(form: $editor.form, issues: editor.issueTexts)
                        }
                    }
                    .padding(Space.page)
                    // Якір на всьому вмісті з полями, а не на квитку: інакше прокрутка зрізала верхні 16 pt, і квиток упирався в шапку.
                    .id(scrollTop)
                }
                // Новий крок починається згори: інакше заголовок питання лишався за краєм, прокрученим ще на минулому.
                .onChange(of: editor.step) { _, _ in proxy.scrollTo(scrollTop, anchor: .top) }
                // Поле з порушенням — у видиму частину: інакше текст під ним лишався за краєм екрана.
                .onChange(of: editor.jump) { _, _ in
                    guard let field = editor.focus else { return }
                    // Червоний текст під полем VoiceOver не помітить сам.
                    if let text = editor.issue(field) { AccessibilityNotification.Announcement(text).post() }
                    // Після зміни кроку поле зʼявляється лише в наступному проході розкладки.
                    DispatchQueue.main.async {
                        if reduceMotion { proxy.scrollTo(field, anchor: .center) }
                        else { withAnimation { proxy.scrollTo(field, anchor: .center) } }
                    }
                }
            }
            actions
        }
        .background(Palette.canvas)
        // Редактор — аркуш над коренем, тож банер кореня з помилкою публікації лишався під ним.
        .notice(model.state?.notice?.presented) { model.app.clearNotice() }
        .onChange(of: editor.form) { _, _ in editor.scheduleSave() }
        // Новий крок — нове питання; якщо крок змінила помилка, вголос каже вона.
        .onChange(of: editor.step) { _, step in
            guard !editor.revealed else { return }
            AccessibilityNotification.Announcement("\(stepLabel(step)). \(step.headline)").post()
        }
        // При згортанні застосунку аркуш не зникає, тож відкладений запис дожимаємо самі.
        .onChange(of: scenePhase) { _, phase in if phase != .active { editor.persist() } }
        .onDisappear { editor.persist() }
        // Зміна закінчилась без підтвердженого запису — відмова: форма лишається редагованою й зберігається.
        .onChange(of: model.state?.mutating) { _, mutating in
            guard mutating == false, editor.submitted, model.state?.completedEventId == nil else { return }
            let error = (model.state?.notice as? AppNoticeFailed)?.error
            editor.failed(fields: (error as? AppErrorInvalidDraft)?.fields ?? [])
        }
        .onChange(of: model.state?.completedEventId) { _, id in
            guard editor.submitted, id != nil else { return }
            editor.finish()
            dismiss()
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

    private func stepLabel(_ step: EditorStep) -> String {
        Copy.onboarding_step("\(step.rawValue + 1)", "\(EditorStep.allCases.count)")
    }

    /// Нова подія зберігається в чернетку й закривається одразу; правки наявної — лише після підтвердження.
    private func close() {
        if editor.dirty { discardingChanges = true } else { editor.persist(); dismiss() }
    }

    /// Закрити, прогрес трьома сегментами і назва режиму. Той самий ряд, що в онбордингу.
    private var wizardHeader: some View {
        HStack(spacing: Space.md) {
            IconPill(glyph: PoruchIcons.close, label: Copy.close, size: 40) { close() }
                .disabled(editor.submitted)
            HStack(spacing: Space.xs) {
                ForEach(EditorStep.allCases) { entry in
                    Capsule().fill(entry.rawValue <= editor.step.rawValue ? Palette.brand : Palette.brandContainer).frame(height: 4)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("\(stepLabel(editor.step)): \(editor.step.title)")
            if editor.canStartOver {
                Button { startingOver = true } label: {
                    Text(Copy.editor_start_over).font(PoruchFont.button).foregroundStyle(Palette.inkSecondary)
                        .fixedSize()
                }
                .tapTarget()
                .disabled(editor.submitted)
            } else {
                Text(editor.editing ? Copy.editor_mode_edit : Copy.editor_mode_new).font(PoruchFont.button).foregroundStyle(Palette.inkSecondary)
                    .fixedSize()
            }
        }
        .frame(height: 56).padding(.horizontal, Space.page).padding(.top, Space.sm)
        // Шапка — хром, як системна навігація: росте до xxLarge, далі напис справа витіснив би прогрес за край.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .motion(value: editor.step)
    }

    private var actions: some View {
        // На великому шрифті дві кнопки поруч не вміщають напис — ставимо одна під одною.
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: Space.md)) : AnyLayout(HStackLayout(spacing: Space.md))
        return layout {
            if editor.step != .about { SecondaryButton(title: Copy.back) { editor.retreat() } }
            PrimaryButton(
                title: !editor.step.isLast ? Copy.next : editor.editing ? Copy.save_changes : Copy.publish,
                loading: model.state?.mutating == true,
                // Не вимкнена, поки крок не заповнено: натискання показує, що саме не так.
                enabled: model.state?.mutating != true
            ) { if editor.step.isLast { editor.submit() } else { editor.advance() } }
        }
        .padding(Space.page)
        .background(Palette.surface.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 1) }
    }
}

/// Квиток «Від людей», що друкується з форми: незаповнене — сірі смуги, як на порожньому квитку, заповнене проступає
/// текстом. Корінець одразу кольору жанру; година, день і місця — з кроку «Коли», бо до нього в полях лише типові значення.
/// `compact` — горизонтальна смужка з корінцем часу праворуч, як рядок «Моїх подій». Для VoiceOver він повтор форми, тож прихований.
private struct DraftTicket: View {
    let form: EditorForm
    let host: String?
    let taken: Int
    let timed: Bool
    var compact = false

    private var title: String { form.title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var place: String { form.address.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Group { if compact { strip } else { full } }
            .motion(value: [title.isEmpty, place.isEmpty, timed, compact])
            .decorative()
    }

    private var parts: (big: String, small: String) {
        timed ? draftStubParts(at: form.starts, zone: form.timeZone) : ("––:––", "")
    }

    /// Смужка на кроках, де людина дивиться на мапу й дати: назва, місце і час на корінці.
    private var strip: some View {
        Ticket(stubColor: categoryStub(form.category), stubLength: 84) {
            VStack(alignment: .leading, spacing: Space.xs) {
                if title.isEmpty { blank(140, height: 10) } else {
                    Text(TitleRules.shared.display(title: title)).font(PoruchFont.brandTitle3).foregroundStyle(Palette.ink).lineLimit(1)
                }
                if place.isEmpty { blank(100, height: 6) } else { MetaLine(glyph: PoruchIcons.pin, text: place) }
            }
            .padding(.horizontal, Space.md).padding(.vertical, Space.md)
        } stub: {
            VStack(spacing: 2) {
                Text(parts.big).font(PoruchFont.numeralSmall).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                if timed { Text(parts.small).font(PoruchFont.overline).kerning(0.6).lineLimit(1).minimumScaleFactor(0.7) }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Space.xs)
        }
    }

    private var full: some View {
        Ticket(vertical: true, stubColor: categoryStub(form.category), stubLength: 64) {
            VStack(alignment: .leading, spacing: Space.xs) {
                if title.isEmpty {
                    blank(160, height: 12); blank(96, height: 12)
                } else {
                    Text(TitleRules.shared.display(title: title)).font(PoruchFont.brandTitle2).foregroundStyle(Palette.ink)
                        .lineLimit(2).transition(.opacity)
                }
                if let host {
                    HStack(spacing: 6) {
                        Avatar(name: host, url: nil, size: 20)
                        Text(Copy.hosted_by(host)).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary).lineLimit(1)
                    }
                }
                Spacer(minLength: Space.sm)
                if place.isEmpty { blank(120, height: 6) } else { MetaLine(glyph: PoruchIcons.pin, text: place).transition(.opacity) }
            }
            .padding(.horizontal, Space.md).padding(.top, Space.md).padding(.bottom, Space.lg)
        } stub: {
            HStack(alignment: .center, spacing: Space.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(categoryName(form.category).uppercased()).font(PoruchFont.overline).kerning(0.6).lineLimit(1)
                    Text(parts.big).font(PoruchFont.numeral).monospacedDigit().lineLimit(1).fixedSize()
                }
                Spacer(minLength: 0)
                if timed {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(parts.small).font(PoruchFont.overline).kerning(0.6).lineLimit(1)
                        HStack(spacing: 3) {
                            PoruchIcon(glyph: PoruchIcons.social, size: 12)
                            Text("\(taken)/\(form.capacity)").font(PoruchFont.overline).monospacedDigit()
                        }
                    }
                    .transition(.opacity)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Space.md)
            // Як у StubTime(row:): відступ зверху врівноважує порожнє місце під цифрами, жанр не липне до перфорації.
            .padding(.top, Space.sm)
        }
    }

    /// Ще не надрукований рядок.
    private func blank(_ width: CGFloat, height: CGFloat) -> some View {
        Capsule().fill(Palette.hairline).frame(width: width, height: height).padding(.vertical, 3)
    }
}

/// Якір верху прокрутки: новий крок відкривається з квитка й питання.
private let scrollTop = "top"

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

private struct AboutStep: View {
    @Binding var form: EditorForm
    /// Тексти під полями значенням, а не замиканням: замикання SwiftUI не порівнює, і крок не перемальовувався.
    let issues: [DraftField: String]
    @FocusState private var focus: DraftField?
    private var descriptionRange: KotlinIntRange { EventRules.shared.descriptionLength }
    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            LabelledField(label: Copy.title, text: $form.title, placeholder: Copy.title_placeholder)
                .focused($focus, equals: .title)
                .submitLabel(.next).onSubmit { focus = .description_ }
            FieldIssue(text: issues[.title])
        }.id(DraftField.title)
        VStack(alignment: .leading, spacing: Space.sm) {
            LabelledField(
                label: Copy.description, text: $form.description,
                placeholder: Copy.description_placeholder,
                hint: Copy.description_hint("\(descriptionRange.first)", "\(form.descriptionLength)", "\(descriptionRange.last)"),
                multiline: true
            )
            .focused($focus, equals: .description_)
            FieldIssue(text: issues[.description_])
        }.id(DraftField.description_)
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(Copy.category_single.uppercased()).font(PoruchFont.overline).kerning(1.0).foregroundStyle(Palette.inkTertiary)
            // Ті самі плитки, що в шторці категорій пошуку: жанр обирають однаково скрізь. Усі одинадцять видно одразу.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: Space.sm)], spacing: Space.md) {
                ForEach(categories, id: \.0) { category in
                    CategoryTile(category: category.0, selected: form.category == category.0) {
                        form.category = category.0
                    }
                }
            }
            FieldIssue(text: issues[.category])
        }.id(DraftField.category)
    }
}

private struct PlaceStep: View {
    @ObservedObject var editor: EventEditorModel
    @State private var mapLatitude: Double
    @State private var mapLongitude: Double
    @State private var picking = false
    @FocusState private var focus: DraftField?

    /// Центр мапи задаємо тут, а не в `onAppear`, інакше перший кадр малюється в (0, 0).
    init(editor: EventEditorModel) {
        _editor = ObservedObject(wrappedValue: editor)
        _mapLatitude = State(initialValue: editor.form.latitude)
        _mapLongitude = State(initialValue: editor.form.longitude)
    }
    private var form: Binding<EditorForm> { $editor.form }
    var body: some View {
        LabelledField(label: Copy.city, text: form.city, placeholder: Copy.city_example)
            .textInputAutocapitalization(.words)
            .submitLabel(.next).onSubmit { focus = .address }
        VStack(alignment: .leading, spacing: Space.sm) {
            LabelledField(
                label: Copy.address, text: form.address,
                placeholder: Copy.address_placeholder,
                hint: Copy.address_hint
            )
            .focused($focus, equals: .address)
            FieldIssue(text: editor.issue(.address))
        }.id(DraftField.address)
        // Підказки одразу під полем, як продовження набору.
        if !editor.addressSuggestions.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(editor.addressSuggestions.enumerated()), id: \.offset) { index, place in
                    if index > 0 { Divider().overlay(Palette.hairline).padding(.horizontal, Space.lg) }
                    Button { editor.pick(place) } label: {
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
        // Мапа лише показує вибране: жести на 240 pt коштували б точності.
        EventMap(
            events: [], latitude: mapLatitude, longitude: mapLongitude,
            // Є крапка — показуємо будинок, а не місто.
            centerZoom: editor.pointChosen ? MapZoom.street : MapZoom.city,
            chosenPoint: editor.form.point,
            interactive: false,
            selected: { _ in },
            moved: { _ in }
        )
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: Corner.md, style: .continuous))
        // Координат не показуємо: людина знає адресу, а не широту.
        MetaLine(
            glyph: editor.pointChosen ? PoruchIcons.checkCircle : PoruchIcons.pin,
            text: editor.pointChosen ? Copy.address_point_set : Copy.address_or_map
        )
        FieldIssue(text: editor.issue(.location)).id(DraftField.location)
        SecondaryButton(title: editor.pointChosen ? Copy.change_point : Copy.choose_point) {
            picking = true
        }
        .frame(maxWidth: .infinity)
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
    }
}

private struct ScheduleStep: View {
    @Binding var form: EditorForm
    /// Тексти під полями значенням, а не замиканням: замикання SwiftUI не порівнює, і крок не перемальовувався.
    let issues: [DraftField: String]
    var body: some View {
        ScheduleFields(starts: $form.starts, ends: $form.ends, zone: form.timeZone).id(DraftField.startsAt)
        FieldIssue(text: issues[.startsAt] ?? issues[.endsAt]).id(DraftField.endsAt)
        TimeZoneNote(zone: form.timeZone, city: form.city, at: form.starts).id(DraftField.timeZone)
        FieldIssue(text: issues[.timeZone])
    }
}

/// Хто може прийти — окремий крок, а не хвіст «Коли»: місця, вік, погодження й чат — частина публікації, а не
/// сховане налаштування.
private struct PeopleStep: View {
    @Binding var form: EditorForm
    /// Тексти під полями значенням, а не замиканням: замикання SwiftUI не порівнює, і крок не перемальовувався.
    let issues: [DraftField: String]
    var body: some View {
        // Число набирають, степер — для дрібних поправок: 1→200 стрілками — двісті дотиків.
        VStack(alignment: .leading, spacing: Space.sm) {
            LabelledField(
                label: Copy.capacity,
                text: Binding(
                    // Стерте поле лишається порожнім, а не стрибає в «0» під курсором.
                    get: { form.capacity == 0 ? "" : "\(form.capacity)" },
                    set: { form.capacity = Int(String($0.filter(\.isNumber).prefix(5))) ?? 0 }
                )
            ) {
                Stepper(Copy.capacity, value: $form.capacity, in: capacityRange).labelsHidden()
            }
            .keyboardType(.numberPad)
            FieldIssue(text: issues[.capacity])
        }.id(DraftField.capacity)
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
                Divider().overlay(Palette.hairline)
                Toggle(isOn: $form.approvalRequired) {
                    VStack(alignment: .leading, spacing: 2) {
                        // Тим самим кеглем, що й «Вік від» і «Верхня межа віку» в цій картці.
                        Text(Copy.approval_label).font(PoruchFont.bodyText).foregroundStyle(Palette.ink)
                        Text(Copy.approval_hint)
                            .font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary)
                    }
                }.tint(Palette.brand)
            }
            .font(PoruchFont.bodyText).foregroundStyle(Palette.ink)
            .padding(Space.lg).cardSurface()
            .id(DraftField.ageLimits)
            FieldIssue(text: issues[.ageLimits])
            // Чат — єдиний канал до учасників. Лише https: решту відкидає і чернетка, і сервер.
            LabelledField(
                label: Copy.contact_label,
                text: Binding(get: { form.contactUrl ?? "" }, set: { form.contactUrl = String($0.prefix(Int(ContactRules.shared.MAX_URL_LENGTH))) }),
                placeholder: "https://t.me/…",
                hint: Copy.contact_editor_hint
            )
            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
            .id(DraftField.contactUrl)
            FieldIssue(text: issues[.contactUrl])
        }
        Text(Copy.photo_after_publish)
            .font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary)
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
private struct ZoomButton: View {
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
