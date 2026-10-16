import SwiftUI
import Shared

/// Публікація в три кроки: що, де, коли. View малює `EventEditorModel`, валідація й збереження там.
struct EventEditor: View {
    let event: Event?
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var editor: EventEditorModel

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
                        // Кожен крок — одне питання великим заголовком, як в онбордингу.
                        VStack(alignment: .leading, spacing: Space.xs) {
                            Text(editor.step.headline).font(PoruchFont.brandDisplay).kerning(-0.5).foregroundStyle(Palette.ink)
                            Text(editor.step.hint).font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary)
                        }.padding(.bottom, Space.xs)
                        switch editor.step {
                        case .about: AboutStep(form: $editor.form, issue: editor.issue)
                        case .place: PlaceStep(editor: editor)
                        case .schedule: ScheduleStep(form: $editor.form, timeZoneFromPlace: editor.timeZoneFromPlace, issue: editor.issue)
                        }
                    }.padding(Space.page)
                }
                // Поле з порушенням — у видиму частину: інакше текст під ним лишався за краєм екрана.
                .onChange(of: editor.jump) { _, _ in
                    guard let field = editor.focus else { return }
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
    }

    /// Закрити, прогрес трьома сегментами і назва режиму. Той самий ряд, що в онбордингу.
    private var wizardHeader: some View {
        HStack(spacing: Space.md) {
            IconPill(glyph: PoruchIcons.close, label: Copy.close, size: 40) { editor.persist(); dismiss() }
            HStack(spacing: Space.xs) {
                ForEach(EditorStep.allCases) { entry in
                    Capsule().fill(entry.rawValue <= editor.step.rawValue ? Palette.brand : Palette.brandContainer).frame(height: 4)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(Copy.onboarding_step("\(editor.step.rawValue + 1)", "\(EditorStep.allCases.count): \(editor.step.title)"))
            Text(editor.editing ? Copy.editor_mode_edit : Copy.editor_mode_new).font(PoruchFont.button).foregroundStyle(Palette.inkSecondary)
        }
        .frame(height: 56).padding(.horizontal, Space.page).padding(.top, Space.sm)
        .motion(value: editor.step)
    }

    private var actions: some View {
        HStack(spacing: Space.md) {
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
    let issue: (DraftField) -> String?
    private var descriptionRange: KotlinIntRange { EventRules.shared.descriptionLength }
    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            LabelledField(label: Copy.title, text: $form.title, placeholder: Copy.title_placeholder)
            FieldIssue(text: issue(.title))
        }.id(DraftField.title)
        VStack(alignment: .leading, spacing: Space.sm) {
            LabelledField(
                label: Copy.description, text: $form.description,
                placeholder: Copy.description_placeholder,
                hint: Copy.description_hint("\(descriptionRange.first)", "\(form.descriptionLength)", "\(descriptionRange.last)"),
                multiline: true
            )
            FieldIssue(text: issue(.description_))
        }.id(DraftField.description_)
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(Copy.category_single.uppercased()).font(PoruchFont.overline).kerning(1.0).foregroundStyle(Palette.inkTertiary)
            // Сітка замість стрічки: всі одинадцять видно одразу, без прокрутки вбік.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.sm), count: 3), spacing: Space.sm) {
                ForEach(categories, id: \.0) { category in
                    CategoryCard(category: category.0, selected: form.category == category.0) {
                        form.category = category.0
                    }
                }
            }
        }
    }
}

private struct PlaceStep: View {
    @ObservedObject var editor: EventEditorModel
    @State private var mapLatitude: Double
    @State private var mapLongitude: Double
    @State private var picking = false

    /// Центр мапи задаємо тут, а не в `onAppear`, інакше перший кадр малюється в (0, 0).
    init(editor: EventEditorModel) {
        _editor = ObservedObject(wrappedValue: editor)
        _mapLatitude = State(initialValue: editor.form.latitude)
        _mapLongitude = State(initialValue: editor.form.longitude)
    }
    private var form: Binding<EditorForm> { $editor.form }
    var body: some View {
        LabelledField(label: Copy.city, text: form.city, placeholder: Copy.city_example)
        VStack(alignment: .leading, spacing: Space.sm) {
            LabelledField(
                label: Copy.address, text: form.address,
                placeholder: Copy.address_placeholder,
                hint: Copy.address_hint
            )
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
    let timeZoneFromPlace: Bool
    let issue: (DraftField) -> String?
    private var zone: TimeZone { TimeZone(identifier: form.timeZone) ?? .current }
    var body: some View {
        ScheduleFields(starts: $form.starts, ends: $form.ends, zone: zone).id(DraftField.startsAt)
        FieldIssue(text: issue(.startsAt) ?? issue(.endsAt)).id(DraftField.endsAt)
        Stepper("\(Copy.capacity_label): \(form.capacity)", value: $form.capacity, in: capacityRange)
            .font(PoruchFont.bodyText).foregroundStyle(Palette.ink)
            .padding(Space.lg).cardSurface()
            .id(DraftField.capacity)
        FieldIssue(text: issue(.capacity))
        TimeZoneNote(zone: form.timeZone, fromPlace: timeZoneFromPlace).id(DraftField.timeZone)
        FieldIssue(text: issue(.timeZone))
        // Хто може прийти — частина публікації, а не сховане налаштування.
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader(title: Copy.who_can_come)
            VStack(spacing: Space.lg) {
                Stepper("\(Copy.age_from): \(form.minAge)", value: $form.minAge, in: ageRange)
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
                        Text(Copy.approval_label).font(PoruchFont.title3).foregroundStyle(Palette.ink)
                        Text(Copy.approval_hint)
                            .font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary)
                    }
                }.tint(Palette.brand)
            }
            .font(PoruchFont.bodyText).foregroundStyle(Palette.ink)
            .padding(Space.lg).cardSurface()
            .id(DraftField.ageLimits)
            FieldIssue(text: issue(.ageLimits))
            Text(Copy.age_limit_hint("\(Int(SafetyRules.shared.MIN_SIGNUP_AGE))"))
                .font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary)
            // Чат — єдиний канал до учасників. Лише https: решту відкидає і чернетка, і сервер.
            LabelledField(
                label: Copy.contact_label,
                text: Binding(get: { form.contactUrl ?? "" }, set: { form.contactUrl = String($0.prefix(Int(ContactRules.shared.MAX_URL_LENGTH))) }),
                placeholder: "https://t.me/…",
                hint: Copy.contact_editor_hint
            )
            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
            .id(DraftField.contactUrl)
            FieldIssue(text: issue(.contactUrl))
        }
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(categoryName(form.category).uppercased()).font(PoruchFont.overline)
                .foregroundStyle(categoryInk(form.category))
            Text(form.title.trimmingCharacters(in: .whitespaces).isEmpty ? Copy.title : TitleRules.shared.display(title: form.title.trimmingCharacters(in: .whitespaces))).font(PoruchFont.brandTitle2).kerning(-0.2).foregroundStyle(Palette.ink)
            MetaLine(glyph: PoruchIcons.pin, text: "\(form.city) · \(form.address)")
            MetaLine(glyph: PoruchIcons.social, text: Copy.seats_short(form.capacity))
        }.padding(Space.lg).frame(maxWidth: .infinity, alignment: .leading).cardSurface()
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
                PageHeader(title: Copy.choose_point_title, back: { dismiss() })
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
