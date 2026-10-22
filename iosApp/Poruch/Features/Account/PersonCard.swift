import SwiftUI
import PhotosUI
import Shared
import AmplitudeSessionReplay

/// Фото, імʼя, дата приходу й лічильники по центру. Спільне для власної шапки й картки людини.
struct ProfileSummary: View {
    let profile: Profile
    var body: some View {
        VStack(spacing: Space.sm) {
            Avatar(name: profile.name, url: profile.avatarUrl, size: 88)
            Text(profile.name).font(PoruchFont.brandTitle1).kerning(-0.4).foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
            // Пошта — один рядок з обрізанням посередині: великий шрифт інакше ламав адресу по літері.
            if let email = profile.email {
                Text(email).font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary).lineLimit(1).truncationMode(.middle)
            }
            if let since = memberSince(profile.memberSince) {
                Text(Copy.profile_member_since("\(since)")).font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary)
            }
            // Лише ненульові: «0 / 0» під іменем новачка нічого не каже. Плитки однакової висоти, навіть коли підпис переноситься.
            let stats = [(Int(profile.organized), Copy.profile_organized), (Int(profile.attended), Copy.profile_attended)]
                .filter { $0.0 > 0 }
            if !stats.isEmpty {
                HStack(spacing: Space.sm) {
                    ForEach(Array(stats.enumerated()), id: \.offset) { _, item in stat(item.0, item.1(item.0)) }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.xs)
            }
        }.frame(maxWidth: .infinity)
    }

    private func stat(_ value: Int, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(PoruchFont.title2).foregroundStyle(Palette.ink)
            Text(label).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary).multilineTextAlignment(.center)
        }
        .padding(Space.md).frame(maxWidth: .infinity, maxHeight: .infinity).cardSurface()
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

    /// «Стежити» за організатором: пуш, коли в нього зʼявиться нова подія. Картку відкривають лише з акаунта.
    private func follow(_ profile: Profile) -> some View {
        let following = model.state?.isFollowing(kind: .organizer, targetId: profile.userId) == true
        return VStack(spacing: Space.xs) {
            FollowPill(following: following) {
                model.app.setFollowing(kind: .organizer, targetId: profile.userId, name: profile.name, following: !following)
            }
            Text(Copy.follow_organizer_hint).font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary)
        }.frame(maxWidth: .infinity)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.md) {
                if let person {
                    if person.loading {
                        PoruchLoader().frame(maxWidth: .infinity).padding(Space.section)
                    } else if let profile = person.profile {
                        ProfileSummary(profile: profile)
                        if let bio = profile.bio {
                            Text(bio).font(PoruchFont.bodyText).foregroundStyle(Palette.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if isMe {
                            Text(Copy.person_you).font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary).frame(maxWidth: .infinity)
                        }
                        if FollowRules.shared.canFollowOrganizer(profile: profile, isMe: isMe) { follow(profile) }
                    } else {
                        VStack(spacing: Space.sm) {
                            Text(Copy.person_unavailable).font(PoruchFont.brandTitle2).kerning(-0.2).foregroundStyle(Palette.ink)
                            Text(Copy.person_unavailable_hint)
                                .font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity)
                    }
                    if !person.loading, let request {
                        Text(Copy.person_request).font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary)
                        HStack(spacing: Space.sm) {
                            SecondaryButton(title: Copy.decline, enabled: model.state?.mutating != true) { request.decline(); dismiss() }
                            PrimaryButton(title: Copy.approve, enabled: model.state?.mutating != true) { request.approve(); dismiss() }
                        }
                    }
                    if !person.loading && !isMe {
                        HStack(spacing: Space.xl) {
                            Button { reporting = true } label: { Text(Copy.chat_report).tapTarget() }.foregroundStyle(Palette.inkSecondary)
                            Button { blocking = true } label: { Text(Copy.block_confirm).tapTarget() }.foregroundStyle(Palette.danger)
                        }.font(PoruchFont.button).frame(maxWidth: .infinity).padding(.top, Space.sm)
                    }
                }
            }
            .padding(Space.page).padding(.top, Space.sm)
        }
        .background(Palette.canvas)
        .confirmationDialog(
            Copy.block_user_body,
            isPresented: $blocking, titleVisibility: .visible
        ) {
            Button(Copy.block_confirm, role: .destructive) {
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

/// Редагування профілю: фото, імʼя, «Про себе» — все зберігається разом кнопкою. Нове фото й «Видалити фото»
/// до «Зберегти» лише позначені, тож «Скасувати» справді нічого не міняє.
struct EditProfileSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let profile: Profile
    @State private var name: String
    @State private var bio: String
    @State private var photo: PhotosPickerItem?
    @State private var photoError: String?
    @State private var reading = false
    /// Обране, але ще не збережене фото: байти для сервера й зменшене для показу.
    @State private var newPhoto: KotlinByteArray?
    @State private var preview: UIImage?
    @State private var removingPhoto = false

    init(profile: Profile) {
        self.profile = profile
        _name = State(initialValue: profile.name)
        _bio = State(initialValue: profile.bio ?? "")
    }

    private var mutating: Bool { model.state?.mutating == true }
    private var savedPhoto: String? { model.state?.library.profile?.avatarUrl ?? nil }
    private var hasPhoto: Bool { preview != nil || (savedPhoto != nil && !removingPhoto) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                Text(Copy.profile_edit).font(PoruchFont.brandTitle1).kerning(-0.4).foregroundStyle(Palette.ink)
                HStack(spacing: Space.lg) {
                    ZStack {
                        if let preview {
                            // Щойно вибране фото — повз `Avatar`, тож і з Session Replay ховаємо його тут.
                            Image(uiImage: preview).resizable().scaledToFill().frame(width: 72, height: 72).clipShape(Circle())
                                .amp_setBlocked(true)
                        } else {
                            Avatar(name: name, url: removingPhoto ? nil : savedPhoto, size: 72)
                        }
                        if reading || mutating { ProgressView() }
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        PhotosPicker(selection: $photo, matching: .images) {
                            Text(hasPhoto ? Copy.profile_photo_change : Copy.profile_photo_add).font(PoruchFont.button).foregroundStyle(Palette.ink)
                                .tapTarget()
                        }.disabled(mutating || reading)
                        if removingPhoto {
                            Button { removingPhoto = false } label: {
                                Text(Copy.undo).font(PoruchFont.button).foregroundStyle(Palette.ink).tapTarget()
                            }.buttonStyle(.plain).disabled(mutating)
                        } else if hasPhoto {
                            Button {
                                if preview != nil { newPhoto = nil; preview = nil; photo = nil } else { removingPhoto = true }
                            } label: {
                                Text(Copy.profile_photo_remove).font(PoruchFont.button).foregroundStyle(Palette.danger).tapTarget()
                            }.buttonStyle(.plain).disabled(mutating)
                        }
                    }
                }
                if let photoError { Text(photoError).font(PoruchFont.caption).foregroundStyle(Palette.danger) }
                Text(removingPhoto ? Copy.remove_photo_undo : Copy.profile_photo_hint)
                    .font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary)
                LabelledField(label: Copy.profile_name, text: $name)
                    .textContentType(.name)
                    .onChange(of: name) { _, value in
                        let limit = Int(AccountRules.shared.nameLength.last)
                        if value.count > limit { name = String(value.prefix(limit)) }
                    }
                LabelledField(label: Copy.profile_bio, text: $bio, hint: Copy.profile_bio_hint, multiline: true)
                    .onChange(of: bio) { _, value in
                        let limit = Int(ProfileRules.shared.BIO_MAX)
                        if value.count > limit { bio = String(value.prefix(limit)) }
                    }
                PrimaryButton(title: Copy.profile_save, loading: mutating,
                              enabled: AccountRules.shared.isName(value: name) && !mutating && !reading) {
                    model.app.saveProfile(
                        name: name, bio: bio, photo: newPhoto, photoType: newPhoto == nil ? nil : "image/jpeg",
                        removePhoto: removingPhoto
                    )
                }
                SecondaryButton(title: Copy.delete_account_cancel, enabled: !mutating) { dismiss() }
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
            case .success(let bytes):
                photoError = nil
                newPhoto = bytes
                removingPhoto = false
                if let data = try? await photo.loadTransferable(type: Data.self) { preview = ThumbnailCache.downsample(data, to: 216) }
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
