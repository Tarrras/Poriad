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
            PageHeader(title: editor.editing ? "Редагування" : "Нова подія", back: { editor.persist(); dismiss() })
            stepBar
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    switch editor.step {
                    case .about: AboutStep(form: $editor.form)
                    case .place: PlaceStep(editor: editor)
                    case .schedule: ScheduleStep(form: $editor.form, timeZoneFromPlace: editor.timeZoneFromPlace)
                    }
                }.padding(Space.page)
            }
            actions
        }
        .background(Palette.canvas)
        .onChange(of: editor.form) { _, _ in editor.scheduleSave() }
        // При згортанні застосунку аркуш не зникає, тож відкладений запис дожимаємо самі.
        .onChange(of: scenePhase) { _, phase in if phase != .active { editor.persist() } }
        .onDisappear { editor.persist() }
        .onChange(of: model.state?.completedEventId) { _, id in
            guard editor.submitted, id != nil else { return }
            editor.finish()
            dismiss()
        }
    }

    private var stepBar: some View {
        HStack(spacing: Space.sm) {
            ForEach(EditorStep.allCases) { entry in
                let reached = entry.rawValue <= editor.step.rawValue
                VStack(alignment: .leading, spacing: Space.sm) {
                    Capsule().fill(reached ? Palette.brand : Palette.hairline).frame(height: 4)
                    Text(entry.title).font(PoruchFont.overline)
                        .foregroundStyle(reached ? Palette.ink : Palette.inkTertiary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, Space.page)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: editor.step)
    }

    private var actions: some View {
        HStack(spacing: Space.md) {
            if editor.step != .about { SecondaryButton(title: "Назад") { editor.retreat() } }
            PrimaryButton(
                title: !editor.step.isLast ? "Далі" : editor.editing ? "Зберегти зміни" : "Опублікувати",
                loading: model.state?.mutating == true,
                enabled: editor.canAdvance && model.state?.mutating != true
            ) { if editor.step.isLast { editor.submit() } else { editor.advance() } }
        }
        .padding(Space.page)
        .background(Palette.surface.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 1) }
    }
}

private struct AboutStep: View {
    @Binding var form: EditorForm
    var body: some View {
        LabelledField(label: "Назва події", text: $form.title, placeholder: "Наприклад: Вечір настільних ігор")
        LabelledField(
            label: "Що плануєте?", text: $form.description,
            placeholder: "Кілька речень про подію", multiline: true
        )
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("КАТЕГОРІЇ").font(PoruchFont.overline).kerning(1.2).foregroundStyle(Palette.inkTertiary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.xs) {
                    ForEach(categories, id: \.0) { category in
                        CategoryTile(category: category.0, selected: form.category == category.0) {
                            form.category = category.0
                        }
                    }
                }
            }
            // Поля всередині смуги, поля сторінки знімаємо.
            .railContentPadding()
            .padding(.horizontal, -Space.page)
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
        LabelledField(label: "Місто", text: form.city, placeholder: "Київ")
        LabelledField(
            label: "Адреса", text: form.address,
            placeholder: "Вулиця, будинок або назва закладу",
            hint: "Почніть набирати — знайдемо на мапі"
        )
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
            symbol: editor.pointChosen ? "checkmark.circle" : "mappin.and.ellipse",
            text: editor.pointChosen ? "Точку зустрічі позначено" : "Знайдіть адресу або вкажіть точку на мапі"
        )
        SecondaryButton(title: editor.pointChosen ? "Змінити точку" : "Обрати точку на мапі") {
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
    private var zone: TimeZone { TimeZone(identifier: form.timeZone) ?? .current }
    var body: some View {
        ScheduleFields(starts: $form.starts, ends: $form.ends, zone: zone)
        Stepper("Місткість: \(form.capacity)", value: $form.capacity, in: capacityRange)
            .font(PoruchFont.bodyText).foregroundStyle(Palette.ink)
            .padding(Space.lg).cardSurface()
        TimeZoneNote(zone: form.timeZone, fromPlace: timeZoneFromPlace)
        // Хто може прийти — частина публікації, а не сховане налаштування.
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader(title: "Хто може прийти")
            VStack(spacing: Space.lg) {
                Stepper("Вік від: \(form.minAge)", value: $form.minAge, in: ageRange)
                Toggle("Верхня межа віку", isOn: Binding(
                    get: { form.maxAge != nil },
                    set: { form.maxAge = $0 ? max(form.minAge, form.minAge + 7) : nil }
                )).tint(Palette.brand)
                if let maximum = form.maxAge {
                    Stepper("Вік до: \(maximum)", value: Binding(
                        get: { maximum }, set: { form.maxAge = $0 }
                    ), in: form.minAge...Int(SafetyRules.shared.MAX_AGE_LIMIT))
                }
                Divider().overlay(Palette.hairline)
                Toggle(isOn: $form.approvalRequired) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Підтверджувати учасників").font(PoruchFont.title3).foregroundStyle(Palette.ink)
                        Text("Ви вирішуєте, хто приєднається до події.")
                            .font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary)
                    }
                }.tint(Palette.brand)
            }
            .font(PoruchFont.bodyText).foregroundStyle(Palette.ink)
            .padding(Space.lg).cardSurface()
            Text("Мінімум \(Int(SafetyRules.shared.MIN_SIGNUP_AGE)) — молодших у застосунку немає.")
                .font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary)
        }
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(categoryName(form.category).uppercased()).font(PoruchFont.overline)
                .foregroundStyle(categoryInk(form.category))
            Text(form.title.isEmpty ? "Назва події" : form.title).font(PoruchFont.title2).foregroundStyle(Palette.ink)
            MetaLine(symbol: "mappin.and.ellipse", text: "\(form.city) · \(form.address)")
            MetaLine(symbol: "person.2", text: "\(form.capacity) місць")
        }.padding(Space.lg).frame(maxWidth: .infinity, alignment: .leading).cardSurface()
        Text("Фото можна додати на сторінці події після публікації.")
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
                PageHeader(title: "Точка зустрічі", back: { dismiss() })
                    .background(Palette.canvas)
                Spacer(minLength: 0)
                HStack {
                    Spacer(minLength: 0)
                    VStack(spacing: Space.sm) {
                        ZoomButton(symbol: "plus", label: "Наблизити") { controller.zoomIn() }
                        ZoomButton(symbol: "minus", label: "Віддалити") { controller.zoomOut() }
                    }
                }
                .padding(Space.lg)
                Spacer(minLength: 0)
                VStack(spacing: Space.md) {
                    // Адреса тут головна, тож і виглядає як головна.
                    HStack(spacing: Space.md) {
                        PoruchIcon(glyph: PoruchIcons.pin, size: 18).foregroundStyle(Palette.inkSecondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(editor.aimAddress.isEmpty ? "Шукаємо адресу…" : editor.aimAddress)
                                .font(PoruchFont.bodyText)
                                .foregroundStyle(editor.aimAddress.isEmpty ? Palette.inkTertiary : Palette.ink)
                                .lineLimit(2)
                            Text("Рухайте мапу — точка лишається в центрі")
                                .font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary)
                        }
                        Spacer(minLength: 0)
                    }
                    PrimaryButton(title: "Готово") {
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
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 44, height: 44)
                .background(Palette.surface, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
