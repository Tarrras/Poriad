import SwiftUI
import Shared

struct DraftData: Codable {
    var title = ""; var description = ""; var category = "social"; var city = ""; var address = ""
    var latitude = 50.45; var longitude = 30.52
    var starts = Date().addingTimeInterval(3600); var ends = Date().addingTimeInterval(7200)
    var timeZone = TimeZone.current.identifier; var capacity = 20; var imageUrl = ""
}
struct EventEditor: View {
    let event: Event?
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var draft = DraftData()
    @State private var step = 0
    @State private var submitted = false
    @State private var mapLatitude = 50.45
    @State private var mapLongitude = 30.52
    @State private var completed = false
    private var storageKey: String { "poruch.draft.\(event?.id ?? "new")" }
    var body: some View {
        NavigationStack {
            Form {
                Section { Text("Крок \(step + 1) із 3").font(.subheadline).foregroundStyle(.secondary) }
                if step == 0 {
                    Section("Що плануємо?") {
                        TextField("Назва події", text: $draft.title)
                        TextField("Розкажіть про подію", text: $draft.description, axis: .vertical).lineLimit(4...10)
                        Picker("Категорія", selection: $draft.category) { ForEach(Array(categories.dropFirst()), id: \.0) { Text($0.1).tag($0.0) } }
                        TextField("Посилання на фото (необов’язково)", text: $draft.imageUrl).keyboardType(.URL).textInputAutocapitalization(.never)
                    }
                } else if step == 1 {
                    Section("Місце зустрічі") {
                        TextField("Місто", text: $draft.city)
                        TextField("Адреса", text: $draft.address)
                        TextField("Широта", value: $draft.latitude, format: .number).keyboardType(.numbersAndPunctuation)
                        TextField("Довгота", value: $draft.longitude, format: .number).keyboardType(.numbersAndPunctuation)
                        Text("Перемістіть мапу: центр визначає точку зустрічі.").font(.caption).foregroundStyle(.secondary)
                        ZStack {
                            EventMap(events: [], latitude: mapLatitude, longitude: mapLongitude, selected: { _ in }, moved: { region in
                                draft.latitude = (region.south + region.north) / 2
                                draft.longitude = (region.west + region.east) / 2
                            })
                            Image(systemName: "mappin").font(.largeTitle).foregroundStyle(.tint).allowsHitTesting(false)
                        }.frame(height: 230)
                    }
                } else {
                    Section("Коли й скільки людей") {
                        DatePicker("Початок", selection: $draft.starts, in: Date()...).environment(\.timeZone, TimeZone(identifier: draft.timeZone) ?? .current)
                        DatePicker("Закінчення", selection: $draft.ends, in: draft.starts...).environment(\.timeZone, TimeZone(identifier: draft.timeZone) ?? .current)
                        TextField("Часовий пояс IANA", text: $draft.timeZone).textInputAutocapitalization(.never)
                        Stepper("Місткість: \(draft.capacity)", value: $draft.capacity, in: 1...10000)
                    }
                    Section("Перевірка") {
                        Text(draft.title).font(.headline)
                        Text("\(draft.city), \(draft.address)")
                        Text("\(categoryName(draft.category)) · \(draft.capacity) місць")
                        Button(event == nil ? "Опублікувати подію" : "Зберегти зміни") { submit() }.disabled(model.state?.mutating == true || draft.title.isEmpty || draft.address.isEmpty || draft.city.isEmpty)
                        if model.state?.mutating == true { ProgressView("Зберігаємо…") }
                    }
                }
                Section {
                    if step < 2 { Button("Далі") { step += 1 }.disabled(step == 0 && draft.title.isEmpty) }
                    if step > 0 { Button("Назад") { step -= 1 } }
                }
            }.navigationTitle(event == nil ? "Нова подія" : "Редагування").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрити") { persist(); dismiss() } } }
                .onAppear(perform: restore)
                .onDisappear(perform: persist)
                .onChange(of: model.state?.completedEventId) { _, id in
                    if submitted && id != nil {
                        completed = true; submitted = false
                        UserDefaults.standard.removeObject(forKey: storageKey)
                        model.app.clearCompletedEvent(); dismiss()
                    }
                }
        }
    }
    private func submit() {
        persist(); model.app.clearCompletedEvent(); submitted = true
        let formatter = ISO8601DateFormatter()
        let value = EventDraft(title: draft.title, description: draft.description, category: draft.category, city: draft.city, address: draft.address, latitude: draft.latitude, longitude: draft.longitude, startsAt: formatter.string(from: draft.starts), endsAt: formatter.string(from: draft.ends), timeZone: draft.timeZone, capacity: Int32(draft.capacity), imageUrl: draft.imageUrl.isEmpty ? nil : draft.imageUrl)
        if let event { model.app.updateEvent(id: event.id, draft: value) } else { model.app.createEvent(draft: value) }
    }
    private func persist() { guard !completed else { return }; if let data = try? JSONEncoder().encode(draft) { UserDefaults.standard.set(data, forKey: storageKey) } }
    private func restore() {
        defer { mapLatitude = draft.latitude; mapLongitude = draft.longitude }
        if let data = UserDefaults.standard.data(forKey: storageKey), let saved = try? JSONDecoder().decode(DraftData.self, from: data) { draft = saved; return }
        if let event {
            draft = DraftData(title: event.title, description: event.description_, category: event.category, city: event.city, address: event.address, latitude: event.latitude, longitude: event.longitude, starts: parseEventDate(event.startsAt) ?? Date(), ends: parseEventDate(event.endsAt) ?? Date(), timeZone: event.timeZone, capacity: Int(event.capacity), imageUrl: event.imageUrl ?? "")
        } else { draft.city = model.state?.cityName ?? "Київ"; draft.latitude = model.state?.cityLatitude ?? 50.45; draft.longitude = model.state?.cityLongitude ?? 30.52 }
    }
}
