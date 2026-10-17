import SwiftUI
import Shared

/// Екран профілю: хто ви, що вам цікаво, що й коли вам писати. Порядок — від людини до пристрою:
/// шапка, підписки, інтереси, сповіщення, приватність, про застосунок; вихід і видалення — в самому низу.
struct ProfileView: View {
    @EnvironmentObject var model: AppModel
    /// Список підписок — окремий екран у стосі вкладки (`RootView.profilePath`).
    var openFollows: () -> Void
    /// Редактор нової події — той самий шлях, що й «+» біля таббару.
    var createEvent: () -> Void
    @State private var newPassword = ""
    @State private var revealed = false
    @State private var showAuth = false
    @State private var deleting = false
    @State private var changingPassword = false
    @State private var editingProfile = false
    @State private var sharingApp: ShareText?
    @State private var birthDate: Date?
    private let latestBirthDate = Calendar.current.date(byAdding: .year, value: -Int(SafetyRules.shared.MIN_SIGNUP_AGE), to: Date()) ?? Date()
    private let earliestBirthDate = Calendar.current.date(byAdding: .year, value: -100, to: Date()) ?? Date.distantPast

    private var signedIn: Bool { model.state?.signedIn == true }
    private var recovering: Bool { model.state?.session.passwordRecovery == true }
    private var blocked: [Attendee] { model.state?.library.blocked ?? [] }

    var body: some View {
        // Як у HomeView: стрічка під смугу статусу, хедер додає відступ.
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) {
                header
                VStack(alignment: .leading, spacing: Space.xxl) {
                    if recovering { recovery }
                    if !signedIn && !recovering { signInPrompt }
                    if model.state?.needsAgeDeclaration == true { ageDeclaration }
                    // Ні організованих, ні відвіданих: замість двох нулів у шапці — перша дія.
                    if signedIn, let profile = model.state?.library.profile, profile.organized == 0, profile.attended == 0 {
                        CreateEventCard(title: Copy.home_create_title, subtitle: Copy.home_create_subtitle, action: createEvent)
                    }
                    if signedIn && !(model.state?.library.follows ?? []).isEmpty { follows }
                    taste
                    notifications
                    privacy
                    about
                    if signedIn { exit }
                    Text(Copy.app_version("\(appVersion)"))
                        .font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary)
                        .frame(maxWidth: .infinity)
                }.padding(.horizontal, Space.page)
            }.padding(.bottom, Space.section)
        }
        .background(Palette.canvas)
        .statusBarBand()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showAuth) { NavigationStack { AuthView() } }
        // На всю висоту: на `.medium` «Скасувати» лежало під згином, а з клавіатурою пароля ховалась і головна дія.
        .sheet(isPresented: $deleting) { DeleteAccountSheet().presentationDetents([.large]) }
        .sheet(isPresented: $changingPassword) { ChangePasswordSheet().presentationDetents([.large]) }
        .sheet(item: $sharingApp) { share in ActivitySheet(items: [share.text]).presentationDetents([.medium, .large]) }
        .sheet(isPresented: $editingProfile) {
            if let profile = model.state?.library.profile { EditProfileSheet(profile: profile).presentationDetents([.large]) }
        }
        // Пароль змінено: шторці нема що показувати, підтвердження побачать у банері кореня.
        .onChange(of: (model.state?.notice as? AppNoticeTold)?.message) { _, message in
            if message == .passwordChanged { changingPassword = false }
        }
        // Сесії більше нема: акаунт видалено, шторці нема що показувати.
        .onChange(of: signedIn) { _, signedIn in if !signedIn { deleting = false; editingProfile = false } }
    }

    /// Аватар і назва по центру, як картка акаунта в Apple Store.
    @ViewBuilder
    private var header: some View {
        if signedIn, let profile = model.state?.library.profile {
            VStack(spacing: Space.md) {
                ProfileSummary(profile: profile)
                if let bio = profile.bio {
                    Text(bio).font(PoruchFont.bodyText).foregroundStyle(Palette.ink).multilineTextAlignment(.center)
                }
                SecondaryButton(title: Copy.profile_edit, glyph: PoruchIcons.edit) { editingProfile = true }
            }
            .padding(.horizontal, Space.page).padding(.top, Space.section).padding(.bottom, Space.sm)
            .frame(maxWidth: .infinity)
        } else {
            genericHeader
        }
    }

    private var genericHeader: some View {
        VStack(spacing: Space.md) {
            PoruchIcon(glyph: PoruchIcons.person, size: 36).foregroundStyle(Palette.onBrandContainer)
                .frame(width: 88, height: 88).background(Palette.brandContainer, in: Circle())
            Text(signedIn ? Copy.account_title : Copy.guest_title).font(PoruchFont.brandTitle1).kerning(-0.4).foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
            Text(signedIn
                 ? Copy.profile_events_hint
                 : Copy.guest_description)
                .font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary).multilineTextAlignment(.center)
        }
        .padding(.horizontal, Space.xxl).padding(.top, Space.section).padding(.bottom, Space.sm)
        .frame(maxWidth: .infinity)
    }

    private var signInPrompt: some View {
        PrimaryButton(title: Copy.profile_guest_cta, glyph: PoruchIcons.enter) { showAuth = true }
            .frame(maxWidth: .infinity)
    }

    private var recovery: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            SectionHeader(title: Copy.new_password)
            LabelledField(label: Copy.password_label, text: $newPassword, hint: Copy.password_hint, secure: !revealed) {
                PasswordRevealToggle(revealed: $revealed)
            }
            .textContentType(.newPassword)
            PrimaryButton(
                title: Copy.save_password,
                enabled: AccountRules.shared.isPassword(value: newPassword) && model.state?.mutating != true
            ) { model.app.updatePassword(password: newPassword) }
        }
    }

    /// Старий акаунт без віку питаємо тут, раз, і кажемо чому. Відмовляє база.
    private var ageDeclaration: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text(Copy.confirm_age_title).font(PoruchFont.cardName).foregroundStyle(Palette.ink)
            Text(Copy.confirm_age_body)
                .font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary)
            BirthDateField(date: $birthDate, range: earliestBirthDate...latestBirthDate)
            PrimaryButton(title: Copy.confirm_age_action, enabled: birthDate != nil) {
                if let birthDate { model.app.declareBirthDate(birthDate: isoDay(birthDate)) }
            }
        }
        .padding(Space.lg).frame(maxWidth: .infinity, alignment: .leading).cardSurface()
    }

    /// Список підписок — окремий екран: тут лише рядок, що каже, що вони є й де. Порожнім його не показуємо.
    private var follows: some View {
        GroupedRows {
            LinkRow(
                glyph: PoruchIcons.bell, title: Copy.follows_title, subtitle: Copy.follows_hint,
                value: "\(model.state?.library.follows.count ?? 0)",
                badge: (model.state?.library.newFollowEvents).flatMap { $0 > 0 ? Copy.follows_new(Int($0)) : nil },
                action: openFollows
            )
        }
    }

    /// Відповіді онбордингу належать пристрою, тож секція є і в гостя. Опитування — дія заголовка, а не ще одна картка під чипами.
    private var taste: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader(title: Copy.interests, actionLabel: Copy.retake_quiz) { model.app.restartOnboarding() }
            FlexibleChips(
                items: categories.map { ($0.0.key, $0.1, $0.0) },
                isSelected: { key in model.state?.interests.contains { $0.key == key } == true }
            ) { model.app.toggleInterest(category: EventCategory.companion.fromKey(key: $0)) }
        }
    }

    /// Усе, що приходить пушем, в одному місці. Дайджест про місто, а не про акаунт: гість його теж отримує.
    private var notifications: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader(title: Copy.notifications_section)
            GroupedRows {
                DigestPreference()
                if signedIn {
                    Divider().overlay(Palette.hairline).padding(.leading, Space.lg)
                    ReminderPreference()
                }
            }
        }
    }

    /// Згода належить пристрою, тож аналітика є і в гостя; пароль і заблоковані — лише з акаунтом.
    private var privacy: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader(title: Copy.privacy_section)
            GroupedRows {
                AnalyticsPreference()
                // Акаунт Google/Apple пароля не має — і міняти нічого.
                if signedIn && model.state?.session.passwordless != true {
                    Divider().overlay(Palette.hairline).padding(.leading, Space.lg)
                    LinkRow(glyph: PoruchIcons.lock, title: Copy.update_password) { changingPassword = true }
                }
            }
            // Блок, який не можна скасувати, не використовуватимуть: список з іменами.
            if !blocked.isEmpty {
                Text(Copy.blocked_section).font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary).padding(.top, Space.sm)
                GroupedRows {
                    ForEach(Array(blocked.enumerated()), id: \.element.userId) { position, person in
                        if position > 0 { Divider().overlay(Palette.hairline).padding(.leading, Space.lg) }
                        HStack(spacing: Space.md) {
                            Text(person.name.isEmpty ? Copy.chat_member : person.name)
                                .font(PoruchFont.cardName).foregroundStyle(Palette.ink)
                            Spacer(minLength: 0)
                            Button { model.app.unblockUser(userId: person.userId) } label: {
                                Text(Copy.unblock).font(PoruchFont.button).foregroundStyle(Palette.ink).tapTarget()
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, Space.lg).padding(.vertical, Space.sm)
                    }
                }
            }
        }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader(title: Copy.about_app)
            Text(Copy.about_app_body)
                .font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary)
            GroupedRows {
                LinkRow(glyph: PoruchIcons.hand, title: Copy.privacy_policy) { open(LegalLinks.shared.PRIVACY) }
                Divider().overlay(Palette.hairline).padding(.leading, Space.lg + 40 + Space.md)
                LinkRow(glyph: PoruchIcons.doc, title: Copy.terms_of_use) { open(LegalLinks.shared.TERMS) }
                Divider().overlay(Palette.hairline).padding(.leading, Space.lg + 40 + Space.md)
                LinkRow(glyph: PoruchIcons.mail, title: Copy.contact_support, subtitle: LegalLinks.shared.SUPPORT_EMAIL) {
                    open("mailto:" + LegalLinks.shared.SUPPORT_EMAIL)
                }
            }
            GroupedRows {
                LinkRow(glyph: PoruchIcons.share, title: Copy.share_app) {
                    model.app.appShared()
                    sharingApp = ShareText(text: Copy.share_app_text("\(StoreLinks.shared.SHARE)"))
                }
                Divider().overlay(Palette.hairline).padding(.leading, Space.lg + 40 + Space.md)
                LinkRow(glyph: PoruchIcons.star, title: Copy.rate_app, subtitle: Copy.rate_app_subtitle_ios) {
                    model.app.rateAppOpened()
                    open(StoreLinks.shared.APP_STORE_REVIEW)
                }
            }
        }
    }

    /// Вихід — звичайна дія, не небезпечна: нейтральна кнопка. Видалення тихіше й червоне, сюди не тягнуться
    /// випадково, а знаходять навмисно; підтвердження — паролем чи Apple у шторці.
    private var exit: some View {
        VStack(spacing: Space.sm) {
            SecondaryButton(title: Copy.logout, glyph: PoruchIcons.signOut) { model.app.signOut() }
            Button { deleting = true } label: {
                Text(Copy.delete_account).font(PoruchFont.button).foregroundStyle(Palette.danger)
                    .multilineTextAlignment(.center).padding(.horizontal, Space.lg).tapTarget()
            }
            .buttonStyle(.plain)
        }
        .padding(.top, Space.lg)
    }

    private func open(_ url: String) { if let url = URL(string: url) { UIApplication.shared.open(url) } }

    /// «1.0.0 (12)» з бандла: те саме число, що бачить магазин.
    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }
}

/// Зміна пароля: поточний доводить власника, як при видаленні; хибний повертає відмову в банері під шторкою.
struct ChangePasswordSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var newPassword = ""
    @State private var revealed = false

    private var mutating: Bool { model.state?.mutating == true }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                Text(Copy.update_password).font(PoruchFont.brandTitle1).kerning(-0.4).foregroundStyle(Palette.ink)
                LabelledField(label: Copy.current_password_label, text: $current, secure: !revealed) {
                    PasswordRevealToggle(revealed: $revealed)
                }
                .textContentType(.password)
                LabelledField(label: Copy.new_password, text: $newPassword, hint: Copy.password_hint, secure: !revealed)
                    .textContentType(.newPassword)
                PrimaryButton(
                    title: Copy.update_password, loading: mutating,
                    enabled: !current.isEmpty && AccountRules.shared.isPassword(value: newPassword)
                ) { model.app.changePassword(current: current, password: newPassword) }
                SecondaryButton(title: Copy.delete_account_cancel, enabled: !mutating) { dismiss() }
            }
            .padding(Space.page).padding(.top, Space.sm)
        }
        .background(Palette.canvas)
        .notice(model.state?.notice?.presented) { model.app.clearNotice() }
    }
}

/// Видалення облікового запису: що зникне, пароль для підтвердження, червона кнопка.
/// Пароль перевіряє сервер (`deleteAccount`); хибний повертає звичайну відмову в банері.
/// Акаунт без пароля підтверджує кнопкою, а акаунт Apple — ще й через Apple: свіжий код
/// дає серверу відкликати токени Apple (App Store 5.1.1(v)).
struct DeleteAccountSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var revealed = false
    @State private var apple = AppleReauthorization()
    @State private var appleFailed = false

    private var mutating: Bool { model.state?.mutating == true }
    private var passwordless: Bool { model.state?.session.passwordless == true }
    private var viaApple: Bool { model.state?.session.viaApple == true }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                Text(Copy.delete_account_title).font(PoruchFont.brandTitle1).kerning(-0.4).foregroundStyle(Palette.ink)
                Text(Copy.delete_account_body)
                    .font(PoruchFont.bodyText).foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                // Google чи Apple з тією ж поштою привʼязуються до наявного акаунта: людина має бачити, що видаляє саме його.
                if let email = model.state?.library.profile?.email { who(email) }
                if !passwordless {
                    LabelledField(label: Copy.password_label, text: $password, hint: Copy.delete_account_password_hint, secure: !revealed) {
                        PasswordRevealToggle(revealed: $revealed)
                    }
                    .textContentType(.password)
                }
                if appleFailed {
                    Text(Copy.apple_sign_in_failed).font(PoruchFont.caption).foregroundStyle(Palette.danger)
                }
                PrimaryButton(
                    title: viaApple ? Copy.delete_account_apple : Copy.delete_account_confirm, glyph: viaApple ? nil : PoruchIcons.trash, symbol: viaApple ? "apple.logo" : nil,
                    tone: Palette.danger, loading: mutating, enabled: passwordless || AccountRules.shared.isPassword(value: password)
                ) { confirm() }
                SecondaryButton(title: Copy.delete_account_cancel, enabled: !mutating) { dismiss() }
            }
            .padding(Space.page).padding(.top, Space.sm)
        }
        .background(Palette.canvas)
        // Банер кореня під шторкою: відмову з хибним паролем показуємо тут.
        .notice(model.state?.notice?.presented) { model.app.clearNotice() }
    }

    /// Який акаунт зникне: пошта й усі способи входу в нього.
    private func who(_ email: String) -> some View {
        let methods = (model.state?.session.providers ?? []).sorted().compactMap { provider -> String? in
            switch provider { case "email": Copy.sign_in_method_email; case "google": "Google"; case "apple": "Apple"; default: nil }
        }
        return VStack(alignment: .leading, spacing: Space.xs) {
            Text(Copy.delete_account_who).font(PoruchFont.overline).kerning(1.0).foregroundStyle(Palette.inkTertiary)
            Text(email).font(PoruchFont.cardName).foregroundStyle(Palette.ink)
            if methods.count > 1 {
                Text(Copy.delete_account_methods(methods.joined(separator: " · ")))
                    .font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.lg).frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Corner.sm, style: .continuous))
    }

    private func confirm() {
        guard viaApple else {
            return model.app.deleteAccount(password: passwordless ? nil : password, appleAuthorizationCode: nil)
        }
        appleFailed = false
        Task {
            do {
                guard let code = try await apple.authorizationCode() else { return appleFailed = true }
                model.app.deleteAccount(password: passwordless ? nil : password, appleAuthorizationCode: code)
            } catch {
                if !SocialSignIn.isCancel(error) { appleFailed = true }
            }
        }
    }
}

/// Перемикач нагадувань. Стан живе у спільному сторі, дозвіл питає система; план рахує `shared`.
struct ReminderPreference: View {
    @EnvironmentObject var model: AppModel
    @State private var denied = false

    private var enabled: Binding<Bool> {
        Binding(
            get: { model.state?.remindersEnabled ?? false },
            set: { isOn in
                guard isOn else { model.app.setRemindersEnabled(enabled: false); return }
                NotificationPermission.request { granted in
                    denied = !granted
                    model.app.setRemindersEnabled(enabled: granted)
                    // Дозвіл є — можна просити токен APNs.
                    if granted { PushDelegate.registerIfAllowed() }
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Toggle(isOn: enabled) {
                Text(Copy.reminders).font(PoruchFont.bodyText).foregroundStyle(Palette.ink)
            }
            .tint(Palette.brand)
            if denied { NotificationsDenied() } else {
                Text(Copy.reminders_note).font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary)
            }
        }
        .padding(Space.lg)
        .notificationsDenied($denied)
    }
}

/// Перемикач дайджесту вихідних. Прапорець пристрою, за замовчуванням так; без дозволу системи
/// він однаково мовчить, тож перемикач показує «увімкнено» лише разом із дозволом.
struct DigestPreference: View {
    @EnvironmentObject var model: AppModel
    @State private var allowed = false
    @State private var denied = false

    private var enabled: Binding<Bool> {
        Binding(
            get: { allowed && (model.state?.digestEnabled ?? true) },
            set: { isOn in
                guard isOn else { model.app.setDigestEnabled(enabled: false); return }
                NotificationPermission.request { granted in
                    allowed = granted
                    denied = !granted
                    model.app.setDigestEnabled(enabled: granted)
                    if granted { PushDelegate.registerIfAllowed() }
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Toggle(isOn: enabled) {
                Text(Copy.digest).font(PoruchFont.bodyText).foregroundStyle(Palette.ink)
            }
            .tint(Palette.brand)
            if denied { NotificationsDenied() } else {
                Text(Copy.digest_note).font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary)
            }
        }
        .padding(Space.lg)
        .notificationsDenied($denied, allowed: $allowed)
    }
}

/// Сповіщення заборонено в системі: каже це одразу, без дотику до перемикача, і веде туди, де дозволяють.
private struct NotificationsDenied: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(Copy.notifications_denied_ios).font(PoruchFont.caption).foregroundStyle(Palette.danger)
            Button {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
            } label: {
                Text(Copy.open_settings).font(PoruchFont.button).foregroundStyle(Palette.ink).tapTarget()
            }
            .buttonStyle(.plain)
        }
    }
}

private extension View {
    /// Стан дозволу системи: при появі й після повернення з Налаштувань, де його могли змінити.
    func notificationsDenied(_ denied: Binding<Bool>, allowed: Binding<Bool>? = nil) -> some View {
        func refresh() async {
            let status = await NotificationPermission.status()
            denied.wrappedValue = status == .denied
            allowed?.wrappedValue = status == .authorized || status == .provisional
        }
        return task { await refresh() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in Task { await refresh() } }
    }
}

/// Перемикач аналітики. Прапорець у спільному сторі; Firebase вмикає й вимикає хук
/// `PoruchAnalytics.collection` (див. `PoruchApplication.init`).
struct AnalyticsPreference: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Toggle(isOn: Binding(
                get: { model.state?.analyticsEnabled ?? true },
                set: { model.app.setAnalyticsEnabled(enabled: $0) }
            )) {
                Text(Copy.analytics).font(PoruchFont.bodyText).foregroundStyle(Palette.ink)
            }
            .tint(Palette.brand)
            Text(Copy.analytics_note)
                .font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary)
        }.padding(Space.lg)
    }
}
