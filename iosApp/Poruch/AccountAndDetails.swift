import SwiftUI
import Shared
import PhotosUI

struct EventDetailView: View {
    @EnvironmentObject var model: AppModel
    @State private var editing = false
    @State private var auth = false
    @State private var cancelling = false
    @State private var photo: PhotosPickerItem?
    @State private var photoError: String?
    var body: some View {
        Group {
            if let event = model.state?.selectedEvent {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if let url = event.imageUrl, let imageURL = URL(string: url) {
                            AsyncImage(url: imageURL) { image in image.resizable().scaledToFill() } placeholder: { Rectangle().fill(.quaternary) }.frame(height: 210).clipped().clipShape(RoundedRectangle(cornerRadius: 20))
                        }
                        Text(categoryName(event.category).uppercased()).font(.caption.weight(.bold)).foregroundStyle(.tint)
                        Text(event.title).font(.largeTitle.bold())
                        Label(eventDate(event), systemImage: "calendar")
                        Label("\(event.city), \(event.address)", systemImage: "mappin.and.ellipse")
                        Label("Організатор: \(event.organizerName)", systemImage: "person.crop.circle")
                        Text(event.description_).font(.body).lineSpacing(5)
                        Text("\(event.attendeeCount) із \(event.capacity) учасників").font(.headline)
                        Button {
                            if model.state?.userId == nil { auth = true }
                            else if event.joined { model.app.leaveEvent(id: event.id) }
                            else { model.app.joinEvent(id: event.id) }
                        } label: {
                            Text(event.status == "cancelled" ? "Подію скасовано" : event.joined ? "Ви берете участь · Вийти" : event.attendeeCount >= event.capacity ? "Місць немає" : "Приєднатися").frame(maxWidth: .infinity).padding(.vertical, 8)
                        }.buttonStyle(.borderedProminent).disabled(model.state?.mutating == true || event.status == "cancelled" || (!event.joined && event.attendeeCount >= event.capacity))
                        Button {
                            if model.state?.userId == nil { auth = true } else { model.app.toggleSaved(id: event.id) }
                        } label: { Label(model.state?.savedIds.contains(event.id) == true ? "Збережено" : "Зберегти", systemImage: model.state?.savedIds.contains(event.id) == true ? "bookmark.fill" : "bookmark").frame(maxWidth: .infinity) }.buttonStyle(.bordered).disabled(model.state?.mutating == true)
                        if event.organizerId == model.state?.userId && event.status != "cancelled" {
                            Button("Редагувати подію") { editing = true }
                            PhotosPicker(selection: $photo, matching: .images) { Label("Змінити фото", systemImage: "photo") }.disabled(model.state?.mutating == true)
                            if let photoError { Text(photoError).foregroundStyle(.red) }
                            Button("Скасувати подію", role: .destructive) { cancelling = true }
                        }
                    }.padding(24)
                }.sheet(isPresented: $editing) { EventEditor(event: event) }
                .confirmationDialog("Скасувати цю подію? Учасники бачитимуть її скасованою.", isPresented: $cancelling, titleVisibility: .visible) { Button("Скасувати подію", role: .destructive) { model.app.cancelEvent(id: event.id) } }
            } else { ProgressView() }
        }.task(id: photo) {
            guard let photo, let event = model.state?.selectedEvent else { return }
            do {
                guard let data = try await photo.loadTransferable(type: Data.self), let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.8) else { photoError = "Не вдалося прочитати фото"; return }
                guard jpeg.count <= 5 * 1024 * 1024 else { photoError = "Оберіть фото до 5 МБ"; return }
                let bytes = KotlinByteArray(size: Int32(jpeg.count))
                for (index, byte) in jpeg.enumerated() { bytes.set(index: Int32(index), value: Int8(bitPattern: byte)) }
                photoError = nil; model.app.uploadEventImage(eventId: event.id, bytes: bytes, contentType: "image/jpeg")
            } catch { photoError = "Не вдалося завантажити фото" }
        }.navigationTitle("Про подію").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $auth) { NavigationStack { ProfileView() } }
    }
}
struct MyEventsView: View {
    @EnvironmentObject var model: AppModel
    @State private var filter = 0
    @State private var detail = false
    var filtered: [Event] {
        (model.state?.myEvents ?? []).filter { event in
            filter == 0 ? event.joined : filter == 1 ? event.organizerId == model.state?.userId : model.state?.savedIds.contains(event.id) == true
        }
    }
    var body: some View {
        VStack {
            Picker("Події", selection: $filter) { Text("Відвідую").tag(0); Text("Організовую").tag(1); Text("Збережені").tag(2) }.pickerStyle(.segmented).padding()
            List(filtered, id: \.id) { event in
                Button { model.app.selectEvent(id: event.id); detail = true } label: { EventRow(event: event) }.buttonStyle(.plain)
            }.overlay { if filtered.isEmpty { ContentUnavailableView(model.state?.userId == nil ? "Увійдіть у профіль" : "Тут будуть ваші події", systemImage: "calendar", description: Text("Знаходьте цікаве, приєднуйтеся та зберігайте на потім.")) } }
        }.navigationTitle("Мої події").task { model.app.loadMyEvents() }.refreshable { model.app.loadMyEvents() }
            .navigationDestination(isPresented: $detail) { EventDetailView() }
    }
}
struct ProfileView: View {
    @EnvironmentObject var model: AppModel
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var register = false
    @AppStorage("poruch.reminders") private var reminders = false
    @State private var reminderDenied = false
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "person.crop.circle").font(.system(size: 48)).foregroundStyle(.tint)
                    Text(model.state?.userId == nil ? "Більше спільного — поруч" : "Ви увійшли").font(.title2.bold())
                    Text("Зберігайте плани, зустрічайте людей і створюйте власні події.").foregroundStyle(.secondary)
                }.padding(.vertical)
            }
            if model.state?.passwordRecovery == true {
                Section("Новий пароль") {
                    SecureField("Щонайменше 6 символів", text: $password).textContentType(.newPassword)
                    Button("Зберегти пароль") { model.app.updatePassword(password: password) }.disabled(password.count < 6 || model.state?.mutating == true)
                }
            } else if model.state?.userId == nil {
                Section(register ? "Створити профіль" : "Вхід") {
                    if register { TextField("Ваше ім’я", text: $name).textContentType(.name) }
                    TextField("Електронна пошта", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Пароль", text: $password).textContentType(register ? .newPassword : .password)
                    Button(register ? "Зареєструватися" : "Увійти") {
                        if register { model.app.signUp(email: email, password: password, name: name) }
                        else { model.app.signIn(email: email, password: password) }
                    }.disabled(email.isEmpty || password.count < 6 || model.state?.mutating == true)
                    Button("Забули пароль?") { model.app.requestPasswordReset(email: email) }.disabled(email.isEmpty || model.state?.mutating == true)
                    Button(register ? "Уже є профіль? Увійти" : "Створити профіль") { register.toggle() }
                }
            } else {
                Section("Ваші інтереси") {
                    ForEach(Array(categories.dropFirst()), id: \.0) { item in
                        Button { model.app.toggleInterest(category: item.0) } label: { HStack { Label(item.1, systemImage: item.2); Spacer(); if model.state?.interests.contains(item.0) == true { Image(systemName: "checkmark.circle.fill") } } }.disabled(model.state?.mutating == true)
                    }
                }
                Section("Нагадування") {
                    Toggle("За годину до події", isOn: $reminders).onChange(of: reminders) { _, enabled in
                        if enabled { model.reminders.request { granted in DispatchQueue.main.async { reminders = granted; reminderDenied = !granted; model.app.loadMyEvents() } } }
                        else if let state = model.state { model.reminders.reconcile(state) }
                    }
                    if reminderDenied { Text("Дозвольте сповіщення в налаштуваннях iOS.").font(.caption).foregroundStyle(.secondary) }
                }
                Section { Button("Вийти", role: .destructive) { model.app.signOut() } }
            }
            Section("Про застосунок") { Text("Поруч — події та люди у вашому місті."); Text("Мапа: MapLibre та OpenFreeMap. Джерела й атрибуція доступні на мапі.").font(.footnote).foregroundStyle(.secondary) }
        }.navigationTitle("Профіль")
    }
}
