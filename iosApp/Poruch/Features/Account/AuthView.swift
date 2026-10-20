import AuthenticationServices
import SwiftUI
import Shared

/// Навіщо гість опинився на екрані входу. Від цього залежать вкладка за замовчуванням і слова під заголовком.
enum AuthReason: Identifiable {
    /// Зайшов сам: з профілю, «Моїх подій», скарги.
    case general
    /// Тап по «Організувати подію» чи «+»: гість найімовірніше новий, тож відкриваємо реєстрацію, а після неї — редактор.
    case create
    case save, join, follow, company

    var id: Self { self }

    /// `action` для `auth_wall`: гість вперся саме в цю дію. Зайшов сам — не стіна.
    var wall: String? {
        switch self {
        case .general: nil
        case .create: "create"
        case .save: "save"
        case .join: "join"
        case .follow: "follow"
        case .company: "companion"
        }
    }
}

/// Вхід і реєстрація: один екран, два режими. Реєстрація — друга половина, а не примітка.
struct AuthView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    /// Висота кнопок Apple і Google росте з Dynamic Type, але не вище 72.
    @ScaledMetric(relativeTo: .body) private var scaledProviderHeight: CGFloat = 52
    private var providerHeight: CGFloat { min(scaledProviderHeight, 72) }
    var reason: AuthReason
    @StateObject private var form: AuthFormModel

    init(reason: AuthReason = .general) {
        self.reason = reason
        _form = StateObject(wrappedValue: AuthFormModel(register: reason == .create))
    }
    /// Крок «Забули пароль?»: окремий екран лише з поштою, щоб кнопка не залежала від форми входу.
    @State private var resetting = false
    /// Збій Google чи Apple до того, як справа дійшла до сервера: банера спільного шару тут не буде.
    @State private var providerError: String?
    @State private var choosingMail = false
    /// `auth_wall` — раз на показ екрана, а не на кожну появу.
    @State private var walled = false

    /// Встановлені поштовики; схеми перелічено в `LSApplicationQueriesSchemes`.
    private var mailApps: [(name: String, url: URL)] {
        [("Пошта", "message://"), ("Gmail", "googlegmail://"), ("Outlook", "ms-outlook://")].compactMap { name, link in
            guard let url = URL(string: link), UIApplication.shared.canOpenURL(url) else { return nil }
            return (name, url)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) {
                header
                if let email = model.state?.session.awaitingConfirmation { confirmation(email) }
                else if resetting { reset }
                else if askingBirthDate { birthDateStep }
                else { fields }
            }.padding(.bottom, Space.section)
        }
        .background(Palette.canvas)
        .toolbar(.hidden, for: .navigationBar)
        // Екран живе в шиті, а банер кореня лишається під ним: помилки й відповіді показуємо тут.
        .notice(model.state?.notice?.presented) { model.app.clearNotice() }
        // Закриваємось, коли вхід доїхав до кінця: після Google чи Apple спільний шар ще питає, чи є
        // дата народження, і без неї екран лишається на кроці дати. Лист відновлення веде на профіль.
        .onChange(of: finished) { _, finished in if finished { dismiss() } }
        .onAppear {
            guard !walled, let action = reason.wall else { return }
            walled = true
            model.app.authWall(action: action)
        }
        .onDisappear { model.app.dismissConfirmationStep() }
        // Лист пішов — повертаємось до входу, банер скаже решту.
        .onChange(of: (model.state?.notice as? AppNoticeTold)?.message) { _, message in
            if message == .recoverySent { resetting = false }
        }
    }

    private var confirming: Bool { model.state?.session.awaitingConfirmation != nil }
    /// Навіщо профіль саме зараз: гість прийшов з дією, і перший рядок під заголовком — про неї.
    private var subtitle: String {
        switch reason {
        case .general: form.register ? Copy.auth_subtitle_signup : Copy.auth_guest_note
        case .create: form.register ? Copy.auth_subtitle_create_signup : Copy.auth_subtitle_create_signin
        case .save: Copy.auth_reason_save
        case .join: Copy.auth_reason_join
        case .follow: Copy.auth_reason_follow
        case .company: Copy.auth_reason_company
        }
    }
    private var askingBirthDate: Bool { model.state?.session.askBirthDate == true }
    private var finished: Bool {
        guard let state = model.state, state.session.userId != nil else { return false }
        return !state.mutating && !state.session.askBirthDate && !state.session.passwordRecovery
    }

    /// Знак застосунку й назва по центру, як вхід в Apple ID. У кутку — закрити аркуш; «назад» лише зі скидання пароля.
    private var header: some View {
        VStack(spacing: Space.md) {
            IconPill(glyph: resetting ? PoruchIcons.chevronLeft : PoruchIcons.close, label: resetting ? Copy.back : Copy.close, size: 40) {
                if resetting { resetting = false } else { dismiss() }
            }
                .frame(maxWidth: .infinity, alignment: .leading)
            PoruchIcon(glyph: confirming ? PoruchIcons.checkCircle : resetting ? PoruchIcons.lock : askingBirthDate ? PoruchIcons.calendar : PoruchIcons.pin, size: 32)
                .foregroundStyle(Palette.onBrand)
                .frame(width: 72, height: 72).background(Palette.brand, in: Circle())
                .decorative()
            Text(confirming ? Copy.auth_check_email_title : resetting ? Copy.auth_reset_title : askingBirthDate ? Copy.auth_birth_date_title
                 : form.register ? Copy.auth_create : Copy.auth_welcome)
                .font(PoruchFont.brandTitle1).kerning(-0.4).foregroundStyle(Palette.ink).multilineTextAlignment(.center)
            Text(confirming ? Copy.auth_check_email_subtitle : resetting ? Copy.auth_reset_subtitle
                 : askingBirthDate ? Copy.auth_birth_date_subtitle : subtitle)
                .font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary).multilineTextAlignment(.center)
                .padding(.horizontal, Space.lg)
        }
        .padding(.horizontal, Space.page).padding(.top, Space.lg)
        .frame(maxWidth: .infinity)
    }

    /// Наступний крок після реєстрації без сесії: куди пішов лист і що з ним робити. Той самий
    /// екран, а не банер: людина має побачити адресу й зрозуміти, що профіль ще не працює.
    private func confirmation(_ email: String) -> some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            VStack(alignment: .leading, spacing: Space.md) {
                PoruchIcon(glyph: PoruchIcons.mail, size: 20)
                    .font(.system(size: 20, weight: .semibold)).foregroundStyle(Palette.onBrandContainer)
                    .frame(width: 48, height: 48).background(Palette.brandContainer, in: Circle())
                Text(Copy.auth_check_email_body("\(email)"))
                    .font(PoruchFont.bodyText).foregroundStyle(Palette.ink)
                Text(Copy.auth_check_email_hint)
                    .font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary)
            }
            .padding(Space.xl).frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(radius: Corner.md, elevation: Elevation.card)
            // Не лише Apple Mail: хто читає пошту в Gmail чи Outlook, обирає свій. Нема жодного — нема й кнопки.
            let apps = mailApps
            if !apps.isEmpty {
                PrimaryButton(title: Copy.auth_open_mail, glyph: PoruchIcons.mail) {
                    if apps.count > 1 { choosingMail = true } else { UIApplication.shared.open(apps[0].url) }
                }
                .confirmationDialog(Copy.auth_open_mail, isPresented: $choosingMail) {
                    ForEach(apps, id: \.name) { app in Button(app.name) { UIApplication.shared.open(app.url) } }
                }
            }
            SecondaryButton(title: Copy.auth_confirmed_login) {
                // Лист підтверджено: пошта вже в полі, лишається пароль.
                model.app.dismissConfirmationStep()
                form.register = false
                form.password = ""
            }
            .frame(maxWidth: .infinity)
        }.padding(.horizontal, Space.page)
    }

    /// Скидання пароля: лише пошта, вже вписана переноситься з форми входу. Лист веде назад у застосунок.
    private var reset: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            LabelledField(label: Copy.email, text: $form.email, placeholder: "you@example.com")
                .textContentType(.emailAddress).keyboardType(.emailAddress)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            PrimaryButton(title: Copy.auth_reset_send, glyph: PoruchIcons.mail, loading: model.state?.mutating == true, enabled: form.emailValid) {
                model.app.requestPasswordReset(email: form.email)
            }
            SecondaryButton(title: Copy.auth_reset_back) { resetting = false }.frame(maxWidth: .infinity)
        }.padding(.horizontal, Space.page)
    }

    /// Apple й Google — найкоротший шлях, тож над формою; для них вхід і реєстрація — одне й те саме.
    private var providers: some View {
        VStack(spacing: Space.md) {
            SignInWithAppleButton(.continue) { request in
                providerError = nil
                request.requestedScopes = [.fullName, .email]
                request.nonce = model.app.idTokenNonce()
            } onCompletion: { result in
                switch result {
                case .success(let authorization):
                    guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                          let apple = SocialSignIn.appleToken(credential) else { return failed("Apple") }
                    model.app.signInWithIdToken(provider: .apple, idToken: apple.token, name: apple.name)
                case .failure(let error):
                    if !SocialSignIn.isCancel(error) { failed("Apple") }
                }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            // Напис Apple росте з висотою кнопки: без цього поруч із більшим Google він лишався дрібним.
            .frame(height: providerHeight).clipShape(buttonShape)
            .disabled(model.state?.mutating == true)
            if SocialSignIn.googleAvailable {
                Button { signInWithGoogle() } label: {
                    HStack(spacing: Space.md) {
                        Image("GoogleG").resizable().frame(width: 20, height: 20).decorative()
                        Text(Copy.continue_with_google).font(PoruchFont.button).foregroundStyle(Palette.ink)
                            .lineLimit(2).multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, Space.lg).padding(.vertical, Space.sm)
                    .frame(maxWidth: .infinity).frame(minHeight: providerHeight)
                    .background(Palette.surface, in: buttonShape)
                    .overlay(buttonShape.stroke(Palette.hairline, lineWidth: 1))
                }
                .buttonStyle(PressableStyle())
                .disabled(model.state?.mutating == true)
            }
            if let providerError {
                Text(providerError).font(PoruchFont.caption).foregroundStyle(Palette.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Згода одразу під Apple й Google: дотик до них уже створює профіль, а форма з кнопкою — нижче.
            consent.frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: Space.md) {
                Rectangle().fill(Palette.hairline).frame(height: 1)
                Text(Copy.auth_or_email).font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary).fixedSize()
                Rectangle().fill(Palette.hairline).frame(height: 1)
            }
        }
    }

    private func signInWithGoogle() {
        providerError = nil
        let nonce = model.app.idTokenNonce()
        Task {
            do {
                guard let token = try await SocialSignIn.googleIdToken(nonce: nonce) else { return }
                model.app.signInWithIdToken(provider: .google, idToken: token, name: nil)
            } catch {
                PoruchLog.shared.w(tag: "auth") { "google sign-in failed: \((error as NSError).domain) \((error as NSError).code)" }
                failed("Google")
            }
        }
    }

    private func failed(_ provider: String) {
        providerError = Copy.provider_sign_in_failed("\(provider)")
    }

    /// Після входу через Google чи Apple: провайдер вік не каже, а «Поряд» — для повнолітніх. Та сама
    /// дата, що при реєстрації поштою; «назад» лишає людину в акаунті, картка віку чекатиме в профілі.
    private var birthDateStep: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            VStack(alignment: .leading, spacing: Space.sm) {
                Text(Copy.birth_date.uppercased()).font(PoruchFont.overline).kerning(1.0).foregroundStyle(Palette.inkTertiary)
                BirthDateField(date: $form.birthDate, range: form.earliestBirthDate...form.latestBirthDate)
                Text(Copy.birth_date_hint)
                    .font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary)
            }
            PrimaryButton(title: Copy.auth_birth_date_continue, loading: model.state?.mutating == true, enabled: form.birthDate != nil) {
                if let date = form.birthDate { model.app.declareBirthDate(birthDate: isoDay(date)) }
            }
        }.padding(.horizontal, Space.page)
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            providers
            // Вхід і реєстрація — два рівноправні режими, тож перемикач угорі, а не кнопка під формою.
            SegmentedPill(items: [Copy.auth_tab_login, Copy.auth_tab_signup], selection: form.register ? 1 : 0) { _ in form.toggleMode() }
            if form.register {
                LabelledField(label: Copy.name, text: $form.name, placeholder: Copy.name_placeholder)
                    .textContentType(.name)
                // Питаємо раз, при реєстрації, і нікому не показуємо: на це спираються вікові межі й модерація.
                VStack(alignment: .leading, spacing: Space.sm) {
                    Text(Copy.birth_date.uppercased()).font(PoruchFont.overline).kerning(1.0).foregroundStyle(Palette.inkTertiary)
                    BirthDateField(date: $form.birthDate, range: form.earliestBirthDate...form.latestBirthDate)
                    Text(Copy.birth_date_hint)
                        .font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary)
                }
            }
            LabelledField(label: Copy.email, text: $form.email, placeholder: "you@example.com")
                .textContentType(.emailAddress).keyboardType(.emailAddress)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            // Вимогу до пароля кажемо лише тому, хто його вигадує.
            LabelledField(label: Copy.password_label, text: $form.password, hint: form.register ? Copy.password_hint : nil, secure: !form.revealed) {
                PasswordRevealToggle(revealed: $form.revealed)
            }
            .textContentType(form.register ? .newPassword : .password)
            // Під час запиту кнопка лишається кольоровою зі спінером: сама блокує дотик, поки `loading`.
            PrimaryButton(
                title: form.register ? Copy.register : Copy.login,
                loading: model.state?.mutating == true,
                enabled: form.canSubmit
            ) { form.submit(with: model.app) }
            if !form.register {
                Button(Copy.forgot_password) { resetting = true }
                    .font(PoruchFont.button).foregroundStyle(Palette.inkSecondary)
                    .frame(maxWidth: .infinity).frame(minHeight: 44)
                    .disabled(model.state?.mutating == true)
            }
        }.padding(.horizontal, Space.page)
    }

    /// Згода під кнопкою реєстрації: назви документів — посилання, але в чорнилі, а не в
    /// системному синьому, щоб рядок лишався підписом, а не закликом. Адреси спільні з Android.
    private var consent: some View {
        var text = AttributedString(Copy.auth_consent_prefix)
        text.append(legalLink(Copy.auth_consent_terms, LegalLinks.shared.TERMS))
        text.append(AttributedString(Copy.auth_consent_and))
        text.append(legalLink(Copy.auth_consent_privacy, LegalLinks.shared.PRIVACY))
        return Text(text)
            .font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary)
            .tint(Palette.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func legalLink(_ title: String, _ url: String) -> AttributedString {
        var link = AttributedString(title)
        link.link = URL(string: url)
        link.underlineStyle = .single
        link.foregroundColor = Palette.ink
        return link
    }
}

/// Стан форми з тими самими правилами валідності, що в спільному модулі.
@MainActor final class AuthFormModel: ObservableObject {
    @Published var email = ""
    @Published var name = ""
    @Published var password = ""
    @Published var revealed = false
    @Published var register: Bool
    /// Порожня, доки людина не обере: дата за замовчуванням пропускала б правило 18+ без відповіді.
    @Published var birthDate: Date?

    /// Мінімум задає сам контрол; база перевірить ще раз.
    let latestBirthDate = Calendar.current.date(byAdding: .year, value: -Int(SafetyRules.shared.MIN_SIGNUP_AGE), to: Date()) ?? Date()
    let earliestBirthDate = Calendar.current.date(byAdding: .year, value: -100, to: Date()) ?? Date.distantPast

    init(register: Bool = false) { self.register = register }

    var emailValid: Bool { AccountRules.shared.isEmail(value: email) }
    var canSubmit: Bool {
        emailValid && AccountRules.shared.isPassword(value: password) &&
            (!register || (AccountRules.shared.isName(value: name) && birthDate.map { $0 <= latestBirthDate } == true))
    }

    /// Пароль не переживає зміну режиму.
    func toggleMode() { register.toggle(); password = "" }

    func submit(with app: PoruchApp) {
        if register, let birthDate { app.signUp(email: email, password: password, name: name, birthDate: isoDay(birthDate)) }
        else if !register { app.signIn(email: email, password: password) }
    }
}

struct PasswordRevealToggle: View {
    @Binding var revealed: Bool
    var body: some View {
        Button { revealed.toggle() } label: {
            PoruchIcon(glyph: revealed ? PoruchIcons.eyeOff : PoruchIcons.eye, size: 20)
                .font(.system(size: 15)).foregroundStyle(Palette.inkSecondary)
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(revealed ? Copy.hide_password : Copy.show_password)
    }
}

/// Дата народження їде як календарний день, без часу й поясу. День — той, що людина бачила в
/// пікері, тобто в поясі пристрою: у UTC локальна північ Києва — ще вчора.
func isoDay(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
}
