import SwiftUI
import Shared

/// Екран акаунта: хто ви, що вам цікаво, як з вами зв'язатися.
struct ProfileView: View {
    @EnvironmentObject var model: AppModel
    /// Список підписок — окремий екран у стосі вкладки (`RootView.profilePath`).
    var openFollows: () -> Void
    @State private var newPassword = ""
    @State private var revealed = false
    @State private var showAuth = false
    @State private var deleting = false
    @State private var changingPassword = false
    @State private var editingProfile = false
    @State private var sharingApp: ShareText?
    @State private var birthDate = Calendar.current.date(byAdding: .year, value: -Int(SafetyRules.shared.MIN_SIGNUP_AGE), to: Date()) ?? Date()
    private let latestBirthDate = Calendar.current.date(byAdding: .year, value: -Int(SafetyRules.shared.MIN_SIGNUP_AGE), to: Date()) ?? Date()
    private let earliestBirthDate = Calendar.current.date(byAdding: .year, value: -100, to: Date()) ?? Date.distantPast

    private var signedIn: Bool { model.state?.signedIn == true }
    private var recovering: Bool { model.state?.session.passwordRecovery == true }

    var body: some View {
        // Як у HomeView: стрічка під смугу статусу, хедер додає відступ.
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) {
                header
                VStack(alignment: .leading, spacing: Space.xxl) {
                    if recovering { recovery }
                    if !signedIn && !recovering { signInPrompt }
                    if model.state?.needsAgeDeclaration == true { ageDeclaration }
                    if signedIn && !(model.state?.library.follows ?? []).isEmpty { follows }
                    taste
                    if signedIn { account }
                    if !(model.state?.library.blocked ?? []).isEmpty { blocked }
                    about
                }.padding(.horizontal, Space.page)
            }.padding(.bottom, Space.section)
        }
        .background(Palette.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showAuth) { NavigationStack { AuthView() } }
        .sheet(isPresented: $deleting) { DeleteAccountSheet().presentationDetents([.medium, .large]) }
        .sheet(isPresented: $changingPassword) { ChangePasswordSheet().presentationDetents([.medium, .large]) }
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
                SecondaryButton(title: "Редагувати профіль", symbol: "pencil") { editingProfile = true }
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
            Text(signedIn ? "Ви з нами" : "Ваші люди — поруч").font(PoruchFont.serifTitle1).kerning(-0.4).foregroundStyle(Palette.ink)
            Text(signedIn
                 ? "Ваші створені, збережені та заплановані події — у вкладці «Мої події»."
                 : "Увійдіть, щоб зберігати цікаве, приєднуватись і створювати власні зустрічі.")
                .font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary).multilineTextAlignment(.center)
        }
        .padding(.horizontal, Space.xxl).padding(.top, Space.section).padding(.bottom, Space.sm)
        .frame(maxWidth: .infinity)
    }

    private var signInPrompt: some View {
        PrimaryButton(title: "Увійти або зареєструватися", symbol: "arrow.right.to.line") { showAuth = true }
            .frame(maxWidth: .infinity)
    }

    private var recovery: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            SectionHeader(title: "Новий пароль")
            LabelledField(label: "Пароль", text: $newPassword, hint: "Щонайменше 8 символів", secure: !revealed) {
                PasswordRevealToggle(revealed: $revealed)
            }
            .textContentType(.newPassword)
            PrimaryButton(
                title: "Зберегти пароль",
                enabled: AccountRules.shared.isPassword(value: newPassword) && model.state?.mutating != true
            ) { model.app.updatePassword(password: newPassword) }
        }
    }

    /// Старий акаунт без віку питаємо тут, раз, і кажемо чому. Відмовляє база.
    private var ageDeclaration: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text("Підтвердьте вік").font(PoruchFont.cardName).foregroundStyle(Palette.ink)
            Text("Ваш обліковий запис створено до того, як ми почали питати вік. Вкажіть дату народження — без неї не вийде приєднатись до події.")
                .font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary)
            BirthDateField(date: $birthDate, range: earliestBirthDate...latestBirthDate)
            PrimaryButton(title: "Вказати дату") { model.app.declareBirthDate(birthDate: isoDay(birthDate)) }
        }
        .padding(Space.lg).frame(maxWidth: .infinity, alignment: .leading).cardSurface()
    }

    /// Блок, який не можна скасувати, не використовуватимуть: список з іменами.
    private var blocked: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader(title: "Заблоковані")
            ForEach(model.state?.library.blocked ?? [], id: \.userId) { person in
                HStack(spacing: Space.md) {
                    Text(person.name.isEmpty ? "Учасник" : person.name)
                        .font(PoruchFont.cardName).foregroundStyle(Palette.ink)
                    Spacer(minLength: 0)
                    Button("Розблокувати") { model.app.unblockUser(userId: person.userId) }
                        .font(PoruchFont.button).foregroundStyle(Palette.ink)
                }.padding(Space.lg).frame(maxWidth: .infinity, alignment: .leading).cardSurface()
            }
        }
    }

    /// Список підписок — окремий екран: тут лише рядок, що каже, що вони є й де. Порожнім його не показуємо.
    private var follows: some View {
        GroupedRows {
            LinkRow(
                symbol: "bell", title: "Підписки", subtitle: "Заклади й організатори",
                value: "\(model.state?.library.follows.count ?? 0)", action: openFollows
            )
        }
    }

    /// Відповіді онбордингу належать пристрою, тож секція є і в гостя.
    private var taste: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader(title: "Ваші інтереси")
            FlexibleChips(
                items: categories.map { ($0.0.key, $0.1, $0.0) },
                isSelected: { key in model.state?.interests.contains { $0.key == key } == true }
            ) { model.app.toggleInterest(category: EventCategory.companion.fromKey(key: $0)) }
            GroupedRows {
                LinkRow(symbol: "sparkles", title: "Налаштувати рекомендації", subtitle: "Пройти опитування ще раз") {
                    model.app.restartOnboarding()
                }
            }
            // Дайджест про місто, а не про акаунт: гість його теж отримує.
            GroupedRows { DigestPreference() }
        }
    }

    private var account: some View {
        VStack(alignment: .leading, spacing: Space.xxl) {
            VStack(alignment: .leading, spacing: Space.md) {
                SectionHeader(title: "Налаштування")
                GroupedRows {
                    ReminderPreference()
                    // Акаунт Google/Apple пароля не має — і міняти нічого.
                    if model.state?.session.passwordless != true {
                        Divider().overlay(Palette.hairline).padding(.leading, Space.lg)
                        LinkRow(symbol: "lock", title: "Змінити пароль") { changingPassword = true }
                    }
                }
            }
            SecondaryButton(title: "Вийти з облікового запису", symbol: "rectangle.portrait.and.arrow.right", tone: Palette.danger) {
                model.app.signOut()
            }
            // Видалення — окрема, важча дія: без заливки, лише червоний текст, і завжди через пароль.
            Button { deleting = true } label: {
                HStack(spacing: Space.sm) {
                    Image(systemName: "trash").font(.system(size: 15, weight: .semibold))
                    Text("Видалити обліковий запис").font(PoruchFont.button).lineLimit(1)
                }
                .foregroundStyle(Palette.danger)
                .padding(.horizontal, Space.xxl).frame(height: 52).frame(maxWidth: .infinity)
                .overlay(Capsule().strokeBorder(Palette.danger.opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(PressableStyle())
        }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader(title: "Про застосунок")
            Text("«Поряд» — події та люди у вашому місті. Мапа: MapLibre та OpenFreeMap.")
                .font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary)
            // Згода належить пристрою, як і нагадування: перемикач є і в гостя.
            GroupedRows { AnalyticsPreference() }
            GroupedRows {
                LinkRow(symbol: "hand.raised", title: "Політика конфіденційності") { open(LegalLinks.shared.PRIVACY) }
                Divider().overlay(Palette.hairline).padding(.leading, Space.lg + 40 + Space.md)
                LinkRow(symbol: "doc.text", title: "Умови користування") { open(LegalLinks.shared.TERMS) }
                Divider().overlay(Palette.hairline).padding(.leading, Space.lg + 40 + Space.md)
                LinkRow(symbol: "envelope", title: "Написати в підтримку", subtitle: LegalLinks.shared.SUPPORT_EMAIL) {
                    open("mailto:" + LegalLinks.shared.SUPPORT_EMAIL)
                }
            }
            GroupedRows {
                LinkRow(symbol: "square.and.arrow.up", title: "Поділитися застосунком") {
                    model.app.appShared()
                    sharingApp = ShareText(text: "Знаходжу концерти, настолки й зустрічі поруч у застосунку «Поряд». Спробуй: \(StoreLinks.shared.SHARE)")
                }
                Divider().overlay(Palette.hairline).padding(.leading, Space.lg + 40 + Space.md)
                LinkRow(symbol: "star", title: "Оцінити застосунок", subtitle: "Відгук в App Store допомагає нам рости") {
                    model.app.rateAppOpened()
                    open(StoreLinks.shared.APP_STORE_REVIEW)
                }
            }
            Text("Версія \(appVersion)")
                .font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary)
        }
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
                Text("Змінити пароль").font(PoruchFont.serifTitle1).kerning(-0.4).foregroundStyle(Palette.ink)
                LabelledField(label: "Поточний пароль", text: $current, secure: !revealed) {
                    PasswordRevealToggle(revealed: $revealed)
                }
                .textContentType(.password)
                LabelledField(label: "Новий пароль", text: $newPassword, hint: "Щонайменше 8 символів", secure: !revealed)
                    .textContentType(.newPassword)
                PrimaryButton(
                    title: "Змінити пароль", loading: mutating,
                    enabled: !current.isEmpty && AccountRules.shared.isPassword(value: newPassword)
                ) { model.app.changePassword(current: current, password: newPassword) }
                SecondaryButton(title: "Скасувати", enabled: !mutating) { dismiss() }
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
                Text("Видалити обліковий запис?").font(PoruchFont.serifTitle1).kerning(-0.4).foregroundStyle(Palette.ink)
                Text("Профіль, участь у подіях, повідомлення й фото буде видалено. Ваші опубліковані події скасуються. Скасувати це буде неможливо.")
                    .font(PoruchFont.bodyText).foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !passwordless {
                    LabelledField(label: "Пароль", text: $password, hint: "Для підтвердження введіть пароль", secure: !revealed) {
                        PasswordRevealToggle(revealed: $revealed)
                    }
                    .textContentType(.password)
                }
                if appleFailed {
                    Text("Apple не підтвердив вхід. Спробуйте ще раз.").font(PoruchFont.caption).foregroundStyle(Palette.danger)
                }
                PrimaryButton(
                    title: viaApple ? "Підтвердити через Apple і видалити" : "Видалити", symbol: viaApple ? "apple.logo" : "trash",
                    tone: Palette.danger, loading: mutating, enabled: passwordless || AccountRules.shared.isPassword(value: password)
                ) { confirm() }
                SecondaryButton(title: "Скасувати", enabled: !mutating) { dismiss() }
            }
            .padding(Space.page).padding(.top, Space.sm)
        }
        .background(Palette.canvas)
        // Банер кореня під шторкою: відмову з хибним паролем показуємо тут.
        .notice(model.state?.notice?.presented) { model.app.clearNotice() }
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
                Text("Сповіщення про мої події").font(PoruchFont.bodyText).foregroundStyle(Palette.ink)
            }
            .tint(Palette.brand)
            Text(denied ? "Дозвольте сповіщення в налаштуваннях iOS." : "Нагадування за годину до початку і нові запити на участь у ваших подіях.")
                .font(PoruchFont.caption).foregroundStyle(denied ? Palette.danger : Palette.inkTertiary)
        }.padding(Space.lg)
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
                Text("Що поруч на вихідних").font(PoruchFont.bodyText).foregroundStyle(Palette.ink)
            }
            .tint(Palette.brand)
            Text(denied ? "Дозвольте сповіщення в налаштуваннях iOS." : "Щопʼятниці о 17:00 — скільки подій у вашому місті на вихідних і що серед них.")
                .font(PoruchFont.caption).foregroundStyle(denied ? Palette.danger : Palette.inkTertiary)
        }
        .padding(Space.lg)
        .task {
            let status = await NotificationPermission.status()
            allowed = status == .authorized || status == .provisional
        }
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
                Text("Аналітика").font(PoruchFont.bodyText).foregroundStyle(Palette.ink)
            }
            .tint(Palette.brand)
            Text("Статистика використання й звіти про збої, без реклами.")
                .font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary)
        }.padding(Space.lg)
    }
}
