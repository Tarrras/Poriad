import SwiftUI
import PhotosUI
import Shared

/// Фото, імʼя, дата приходу й лічильники по центру. Спільне для власної шапки й картки людини.
struct ProfileSummary: View {
    let profile: Profile
    var body: some View {
        VStack(spacing: Space.sm) {
            Avatar(name: profile.name, url: profile.avatarUrl, size: 88)
            Text(profile.name).font(PoruchFont.title1).titleTracking().foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
            if let email = profile.email {
                Text(email).font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary)
            }
            if let since = memberSince(profile.memberSince) {
                Text("На «Поряд» з \(since)").font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary)
            }
            HStack(spacing: Space.sm) {
                stat(Int(profile.organized), "Як організатор")
                stat(Int(profile.attended), "Як учасник")
            }.padding(.top, Space.xs)
        }.frame(maxWidth: .infinity)
    }

    private func stat(_ value: Int, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(PoruchFont.title2).foregroundStyle(Palette.ink)
            Text(label).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary)
        }
        .frame(maxWidth: .infinity).padding(Space.md).cardSurface()
        .accessibilityElement(children: .combine)
    }
}

/// «вересня 2026»: родовий відмінок, бо стоїть після «з».
private func memberSince(_ iso: String?) -> String? {
    guard let iso else { return nil }
    let parser = ISO8601DateFormatter()
    parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let date = parser.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return nil }
    let format = DateFormatter()
    format.locale = Locale(identifier: "uk_UA")
    format.dateFormat = "MMMM yyyy"
    return format.string(from: date)
}

/// Дії з запитом на участь, коли картку відкрив організатор.
struct PersonRequest {
    let approve: () -> Void
    let decline: () -> Void
}

/// Картка людини зі стану (`state.person`). Скарга й блокування — для всіх, крім себе.
/// Блокування питає підтвердження; `onBlocked` — щоб екран під карткою зміг піти.
struct PersonSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var request: PersonRequest?
    var onBlocked: (String) -> Void = { _ in }
    @State private var reporting = false
    @State private var blocking = false

    private var person: PersonState? { model.state?.person }
    private var isMe: Bool { person?.userId == model.state?.session.userId }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.md) {
                if let person {
                    if person.loading {
                        ProgressView().frame(maxWidth: .infinity).padding(Space.section)
                    } else if let profile = person.profile {
                        ProfileSummary(profile: profile)
                        if let bio = profile.bio {
                            Text(bio).font(PoruchFont.bodyText).foregroundStyle(Palette.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if isMe {
                            Text("Це ви").font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary).frame(maxWidth: .infinity)
                        }
                    } else {
                        VStack(spacing: Space.sm) {
                            Text("Профіль недоступний").font(PoruchFont.title2).foregroundStyle(Palette.ink)
                            Text("Людина приховала профіль від вас або його обмежила модерація.")
                                .font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity)
                    }
                    if !person.loading, let request {
                        Text("Хоче приєднатися до вашої події").font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary)
                        HStack(spacing: Space.sm) {
                            SecondaryButton(title: "Відхилити", enabled: model.state?.mutating != true) { request.decline(); dismiss() }
                            PrimaryButton(title: "Прийняти", enabled: model.state?.mutating != true) { request.approve(); dismiss() }
                        }
                    }
                    if !person.loading && !isMe {
                        HStack(spacing: Space.xl) {
                            Button("Поскаржитись") { reporting = true }.foregroundStyle(Palette.inkSecondary)
                            Button("Заблокувати") { blocking = true }.foregroundStyle(Palette.danger)
                        }.font(PoruchFont.button).frame(maxWidth: .infinity).padding(.top, Space.sm)
                    }
                }
            }
            .padding(Space.page).padding(.top, Space.sm)
        }
        .background(Palette.canvas)
        .confirmationDialog(
            "Ви більше не побачите подій цієї людини, а вона — ваших. Скасувати можна у профілі.",
            isPresented: $blocking, titleVisibility: .visible
        ) {
            Button("Заблокувати", role: .destructive) {
                guard let id = person?.userId else { return }
                model.app.blockUser(userId: id)
                dismiss()
                onBlocked(id)
            }
        }
        .sheet(isPresented: $reporting) {
            ReportSheet(target: .person) { reason, details in
                if let id = person?.userId { model.app.reportUser(userId: id, reason: reason, details: details) }
            }.presentationDetents([.medium, .large])
        }
    }
}

extension View {
    /// Шторка картки людини. Прапорець свій у кожного екрана: стан один на застосунок, а деталі
    /// лишаються в стосі під чатом — без прапорця шторку намагались би показати обидва.
    /// Закриття жестом закриває й картку в стані.
    func personSheet(_ model: AppModel, isPresented: Binding<Bool>, request: @escaping (String) -> PersonRequest? = { _ in nil }, onBlocked: @escaping (String) -> Void = { _ in }) -> some View {
        sheet(isPresented: Binding(
            get: { isPresented.wrappedValue && model.state?.person != nil },
            set: { if !$0 { isPresented.wrappedValue = false; model.app.closePerson() } }
        )) {
            PersonSheet(request: model.state?.person.flatMap { request($0.userId) }, onBlocked: onBlocked)
                .presentationDetents([.medium, .large])
        }
    }
}

/// Редагування профілю: фото, імʼя, «Про себе». Фото йде одразу після вибору, текст — кнопкою.
struct EditProfileSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let profile: Profile
    @State private var name: String
    @State private var bio: String
    @State private var photo: PhotosPickerItem?
    @State private var photoError: String?
    @State private var reading = false

    init(profile: Profile) {
        self.profile = profile
        _name = State(initialValue: profile.name)
        _bio = State(initialValue: profile.bio ?? "")
    }

    private var mutating: Bool { model.state?.mutating == true }
    /// Фото зі стану: після завантаження показуємо нове, не чекаючи закриття.
    private var avatarUrl: String? { model.state?.library.profile?.avatarUrl ?? nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                Text("Редагувати профіль").font(PoruchFont.title1).titleTracking().foregroundStyle(Palette.ink)
                HStack(spacing: Space.lg) {
                    ZStack {
                        Avatar(name: name, url: avatarUrl, size: 72)
                        if reading || mutating { ProgressView() }
                    }
                    VStack(alignment: .leading, spacing: Space.sm) {
                        PhotosPicker(selection: $photo, matching: .images) {
                            Text(avatarUrl == nil ? "Додати фото" : "Змінити фото").font(PoruchFont.button).foregroundStyle(Palette.ink)
                        }.disabled(mutating || reading)
                        if avatarUrl != nil {
                            Button("Видалити фото") { model.app.removeAvatar() }
                                .font(PoruchFont.button).foregroundStyle(Palette.danger).disabled(mutating)
                        }
                    }
                }
                if let photoError { Text(photoError).font(PoruchFont.caption).foregroundStyle(Palette.danger) }
                Text("Фото й «Про себе» бачать організатори та учасники спільних подій.")
                    .font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary)
                LabelledField(label: "Імʼя", text: $name)
                    .textContentType(.name)
                    .onChange(of: name) { _, value in
                        let limit = Int(AccountRules.shared.nameLength.last)
                        if value.count > limit { name = String(value.prefix(limit)) }
                    }
                LabelledField(label: "Про себе", text: $bio, hint: "Кілька слів для організаторів і учасників: чим займаєтесь, що любите. До 300 знаків.", multiline: true)
                    .onChange(of: bio) { _, value in
                        let limit = Int(ProfileRules.shared.BIO_MAX)
                        if value.count > limit { bio = String(value.prefix(limit)) }
                    }
                PrimaryButton(title: "Зберегти", loading: mutating,
                              enabled: AccountRules.shared.isName(value: name) && !mutating) {
                    model.app.saveProfile(name: name, bio: bio)
                }
                SecondaryButton(title: "Скасувати", enabled: !mutating) { dismiss() }
            }
            .padding(Space.page).padding(.top, Space.sm)
        }
        .background(Palette.canvas)
        // Банер кореня під шторкою: відмову стоп-словника чи мережі показуємо тут.
        .notice(model.state?.notice?.presented) { model.app.clearNotice() }
        .task(id: photo) {
            guard let photo else { return }
            reading = true
            switch await pickedJPEG(photo, maxPixel: CGFloat(ProfileRules.shared.AVATAR_SIDE)) {
            case .success(let bytes): photoError = nil; model.app.setAvatar(bytes: bytes, contentType: "image/jpeg")
            case .failure(let problem): photoError = problem.message
            }
            reading = false
        }
        // Збережено — шторці нема що показувати; підтвердження побачать у банері кореня.
        .onChange(of: (model.state?.notice as? AppNoticeTold)?.message) { _, message in
            if message == .changesSaved { dismiss() }
        }
    }
}
