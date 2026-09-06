import SwiftUI
import Shared

/// Publishing in three steps: what, where, when. The view draws [EventEditorModel] and forwards
/// edits to it; validation and persistence live there.
struct EventEditor: View {
    let event: Event?
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                    case .place: PlaceStep(form: $editor.form)
                    case .schedule: ScheduleStep(form: $editor.form)
                    }
                }.padding(Space.page)
            }
            actions
        }
        .background(Palette.canvas)
        .onChange(of: editor.form) { _, _ in editor.persist() }
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
                }.padding(.horizontal, 2)
            }
        }
    }
}

private struct PlaceStep: View {
    @Binding var form: EditorForm
    @State private var mapLatitude = 0.0
    @State private var mapLongitude = 0.0
    var body: some View {
        LabelledField(label: "Місто", text: $form.city, placeholder: "Київ")
        LabelledField(
            label: "Адреса", text: $form.address, placeholder: "Вулиця, будинок, орієнтир",
            hint: "Перемістіть мапу: центр визначає точку зустрічі."
        )
        ZStack {
            EventMap(events: [], latitude: mapLatitude, longitude: mapLongitude, selected: { _ in }, moved: { region in
                form.latitude = (region.south + region.north) / 2
                form.longitude = (region.west + region.east) / 2
            })
            PoruchIcon(glyph: PoruchIcons.pin, size: 32)
                .foregroundStyle(categoryColor(form.category)).allowsHitTesting(false)
        }
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: Corner.md, style: .continuous))
        MetaLine(symbol: "location", text: String(format: "%.5f, %.5f", form.latitude, form.longitude))
        // The map only reads its starting point once, so it is captured before the first draw.
        .onAppear { mapLatitude = form.latitude; mapLongitude = form.longitude }
    }
}

private struct ScheduleStep: View {
    @Binding var form: EditorForm
    private var zone: TimeZone { TimeZone(identifier: form.timeZone) ?? .current }
    var body: some View {
        VStack(spacing: Space.lg) {
            DatePicker("Початок", selection: $form.starts, in: Date()...).environment(\.timeZone, zone)
            DatePicker("Закінчення", selection: $form.ends, in: form.starts...).environment(\.timeZone, zone)
            Stepper("Місткість: \(form.capacity)", value: $form.capacity, in: capacityRange)
        }
        .font(PoruchFont.bodyText).foregroundStyle(Palette.ink)
        .padding(Space.lg).cardSurface()
        LabelledField(label: "Часовий пояс IANA", text: $form.timeZone, placeholder: "Europe/Kyiv")
            .textInputAutocapitalization(.never)
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(categoryName(form.category).uppercased()).font(PoruchFont.overline)
                .foregroundStyle(categoryColor(form.category))
            Text(form.title.isEmpty ? "Назва події" : form.title).font(PoruchFont.title2).foregroundStyle(Palette.ink)
            MetaLine(symbol: "mappin.and.ellipse", text: "\(form.city) · \(form.address)")
            MetaLine(symbol: "person.2", text: "\(form.capacity) місць")
        }.padding(Space.lg).frame(maxWidth: .infinity, alignment: .leading).cardSurface()
        Text("Фото можна додати на сторінці події після публікації.")
            .font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary)
    }
}

/// The same range the server's CHECK constraint enforces.
private var capacityRange: ClosedRange<Int> {
    Int(EventRules.shared.capacity.first)...Int(EventRules.shared.capacity.last)
}
