import AuthenticationServices
import SwiftUI
import Shared

/// Навіщо гість опинився на екрані входу. Від цього залежать слова під заголовком.
enum AuthReason: Identifiable {
    /// Зайшов сам: з профілю, «Моїх подій», скарги.
    case general
    /// «Опублікувати» в редакторі гостя: після входу подія публікується сама (`AppState.publishAfterSignIn`).
    case create
    case join, follow, company

    var id: Self { self }

    /// `action` для `auth_wall`: гість вперся саме в цю дію. Зайшов сам — не стіна.
    var wall: String? {
        switch self {
        // `create` рахує сам спільний шар, коли гість тисне «Опублікувати».
        case .general, .create: nil
        case .join: "join"
        case .follow: "follow"
        case .company: "companion"
        }
    }
}

/// Вхід (docs/design-wow-1.5.md, «Вхід кодом з пошти»): Apple, Google, далі одне поле пошти й «Надіслати код». Пароль —
/// посиланням «Увійти з паролем» для наявних акаунтів. Реєстрації з паролем нема (рішення власника 02.11): новий профіль
/// — кодом, Apple чи Google, а «Мені вже є 18» питає крок «Ще один крок».
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
        _form = StateObject(wrappedValue: AuthFormModel())
    }
    /// Крок «Забули пароль?»: окремий екран лише з поштою, щоб кнопка не залежала від форми входу.
    @State private var resetting = false
    /// Збій Google чи Apple до того, як справа дійшла до сервера: банера спільного шару тут не буде.
    @State private var providerError: String?
    @State private var choosingMail = false
    /// Код пішов — поле коду. «Інша пошта» повертає до поля пошти, хоч `awaitingCode` ще той.
    @State private var codeMode = false
    /// «Увійти з паролем»: форма пошти й пароля для наявних акаунтів.
    @State private var passwordMode = false
    @State private var code = ""
    /// Коли можна просити новий код: Supabase Auth шле не частіше за раз на 60 с.
    @State private var resendAt = Date.distantPast
    /// `auth_wall` — раз на показ екрана, а не на кожну появу.
    @State private var walled = false
    /// «Я підтвердив — увійти»: форма входу, хоч `awaitingConfirmation` ще стоїть. Без `dismissConfirmationStep`, бо той
    /// скасував би й публікацію гостя з «Опублікувати»; крок зникне сам із входом.
    @State private var confirmedLogin = false

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
                if let email = confirmingEmail { confirmation(email) }
                else if resetting { reset }
                else if askingBirthDate { adultStep }
                else if passwordMode { passwordForm }
                else if let sent = sentCode { codeEntry(sent) }
                else { start }
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
        // Нова реєстрація чекає на лист — знову крок «перевірте пошту».
        .onChange(of: model.state?.session.awaitingConfirmation) { _, email in if email != nil { confirmedLogin = false } }
        // Код пішов (і на іншу пошту): поле коду, порожнє.
        .onChange(of: model.state?.session.awaitingCode) { _, email in
            guard email != nil else { return }
            codeMode = true
            code = ""
        }
    }

    private var confirmingEmail: String? { confirmedLogin ? nil : model.state?.session.awaitingConfirmation }
    private var sentCode: String? { codeMode ? model.state?.session.awaitingCode : nil }
    private var confirming: Bool { confirmingEmail != nil }
    /// Навіщо профіль саме зараз: гість прийшов з дією, і перший рядок під заголовком — про неї.
    private var subtitle: String {
        switch reason {
        case .general: Copy.auth_guest_note
        case .create: Copy.auth_subtitle_publish
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

    /// Скидання пароля, вхід паролем чи поле коду: «назад» замість «закрити».
    private var inSubstep: Bool { (resetting || passwordMode || sentCode != nil) && !confirming && !askingBirthDate }

    /// Знак застосунку й назва по центру, як вхід в Apple ID. У кутку — закрити аркуш; «назад» — з підкроків.
    private var header: some View {
        let coding = sentCode.flatMap { confirming || askingBirthDate || passwordMode ? nil : $0 }
        return VStack(spacing: Space.md) {
            IconPill(glyph: inSubstep ? PoruchIcons.chevronLeft : PoruchIcons.close, label: inSubstep ? Copy.back : Copy.close, size: 40) {
                if resetting { resetting = false } else if passwordMode { passwordMode = false }
                else if coding != nil { codeMode = false } else { dismiss() }
            }
                .frame(maxWidth: .infinity, alignment: .leading)
            // Знак 64: на першому екрані SE над поштою мають уміститись Apple й Google.
            PoruchIcon(glyph: confirming ? PoruchIcons.checkCircle : resetting ? PoruchIcons.lock : askingBirthDate ? PoruchIcons.person
                       : coding != nil ? PoruchIcons.mail : PoruchIcons.pin, size: 28)
                .foregroundStyle(Palette.onBrand)
                .frame(width: 64, height: 64).background(Palette.brand, in: Circle())
                .decorative()
            Text(confirming ? Copy.auth_check_email_title : resetting ? Copy.auth_reset_title : askingBirthDate ? Copy.auth_birth_date_title
                 : coding != nil ? Copy.auth_code_field : Copy.auth_welcome)
                .font(PoruchFont.brandTitle1).kerning(-0.4).foregroundStyle(Palette.ink).multilineTextAlignment(.center)
            Text(confirming ? Copy.auth_check_email_subtitle : resetting ? Copy.auth_reset_subtitle
                 : askingBirthDate ? Copy.auth_adult_subtitle : coding.map { Copy.auth_code_sent($0) } ?? subtitle)
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
                confirmedLogin = true
                passwordMode = true
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
            // Згода одразу під Apple й Google: дотик до них уже створює профіль, тож її видно до нього й на SE. Під
            // «Надіслати код» вона йшла за згин.
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

    /// Лист з кодом; відлік до наступного — з самого тапу. Повтор на ту саму пошту `awaitingCode` не міняє, тож поле
    /// коду відкриваємо самі: код на неї вже йшов. Пошту — без пробілів, як її зберігає спільний шар: QuickType лишає
    /// пробіл у кінці, і без цього поле коду після «Інша пошта» не з'являлось.
    private func send(_ email: String) {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        resendAt = Date().addingTimeInterval(codeResendDelay)
        providerError = nil
        if model.state?.session.awaitingCode == email { codeMode = true; code = "" }
        model.app.sendSignInCode(email: email)
    }

    private func failed(_ provider: String) {
        providerError = Copy.provider_sign_in_failed("\(provider)")
    }

    /// Після входу через Google, Apple чи код: провайдер вік не каже, а «Поряд» — для повнолітніх. Та сама
    /// галочка, що при реєстрації поштою; «назад» лишає людину в акаунті, картка віку чекатиме в профілі.
    private var adultStep: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            AdultCheckbox(checked: $form.adult)
            PrimaryButton(title: Copy.auth_birth_date_continue, loading: model.state?.mutating == true, enabled: form.adult) {
                model.app.confirmAdult()
            }
        }.padding(.horizontal, Space.page)
    }

    /// Перший екран: Apple, Google, згода, пошта й «Надіслати код» — ті самі `/auth/v1/otp` і `/verify`, що на сайті.
    /// Пароль — посиланням для тих, хто його має.
    private var start: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            providers
            LabelledField(label: Copy.email, text: $form.email, placeholder: "you@example.com")
                .textContentType(.emailAddress).keyboardType(.emailAddress)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .submitLabel(.send).onSubmit { if form.emailValid { send(form.email) } }
            PrimaryButton(title: Copy.auth_code_send, glyph: PoruchIcons.mail, loading: model.state?.mutating == true, enabled: form.emailValid) {
                send(form.email)
            }
            Button(Copy.auth_password_link) { providerError = nil; passwordMode = true }
                .font(PoruchFont.button).foregroundStyle(Palette.inkSecondary)
                .frame(maxWidth: .infinity).frame(minHeight: 44)
                .disabled(model.state?.mutating == true)
        }.padding(.horizontal, Space.page)
    }

    /// Код з листа: великими цифрами, як на сайті, з автозаповненням з «Пошти». Під «Увійти» — повтор і інша пошта.
    private func codeEntry(_ sent: String) -> some View {
        let mutating = model.state?.mutating == true
        let submit = { model.app.verifySignInCode(email: sent, code: code.trimmingCharacters(in: .whitespaces)) }
        return VStack(alignment: .leading, spacing: Space.lg) {
            TextField(Copy.auth_code_field, text: $code, prompt: Text("000000").foregroundStyle(Palette.inkTertiary))
                .font(.custom("SofiaSansExtraCondensed-ExtraBold", size: 28, relativeTo: .title2)).kerning(6).monospacedDigit()
                .foregroundStyle(Palette.ink).tint(Palette.ink).textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .textContentType(.oneTimeCode).keyboardType(.numberPad)
                .padding(.horizontal, Space.lg).frame(minHeight: 64)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: Corner.md, style: .continuous))
            PrimaryButton(title: Copy.login, loading: mutating, enabled: AccountRules.shared.isCode(value: code)) { submit() }
            // Відлік щосекунди лише в цьому рядку, а не у всьому екрані. Текстом в один ряд; на великому шрифті — стовпчиком.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let left = Int(resendAt.timeIntervalSince(context.date).rounded(.up))
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Space.lg) { resend(left, sent, mutating); Spacer(minLength: 0); otherEmail(mutating) }
                    VStack(alignment: .leading, spacing: 0) { resend(left, sent, mutating); otherEmail(mutating) }
                }
            }
        }.padding(.horizontal, Space.page)
    }

    private func resend(_ left: Int, _ sent: String, _ mutating: Bool) -> some View {
        Button(left > 0 ? Copy.auth_code_resend_in("\(left)") : Copy.auth_code_resend) { send(sent) }
            .font(PoruchFont.button).foregroundStyle(left > 0 ? Palette.inkTertiary : Palette.inkSecondary)
            .monospacedDigit().fixedSize().frame(minHeight: 44)
            .disabled(left > 0 || mutating)
    }

    private func otherEmail(_ mutating: Bool) -> some View {
        Button(Copy.auth_code_other_email) { codeMode = false }
            .font(PoruchFont.button).foregroundStyle(Palette.inkSecondary)
            .fixedSize().frame(minHeight: 44)
            .disabled(mutating)
    }

    /// «Увійти з паролем»: пошта, пароль, «Забули пароль?».
    private var passwordForm: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            LabelledField(label: Copy.email, text: $form.email, placeholder: "you@example.com")
                .textContentType(.emailAddress).keyboardType(.emailAddress)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            LabelledField(label: Copy.password_label, text: $form.password, secure: !form.revealed) {
                PasswordRevealToggle(revealed: $form.revealed)
            }
            .textContentType(.password)
            // Під час запиту кнопка лишається кольоровою зі спінером: сама блокує дотик, поки `loading`.
            PrimaryButton(title: Copy.login, loading: model.state?.mutating == true, enabled: form.canSubmit) {
                model.app.signIn(email: form.email, password: form.password)
            }
            Button(Copy.forgot_password) { resetting = true }
                .font(PoruchFont.button).foregroundStyle(Palette.inkSecondary)
                .frame(maxWidth: .infinity).frame(minHeight: 44)
                .disabled(model.state?.mutating == true)
        }.padding(.horizontal, Space.page)
    }

    /// Згода під Apple й Google: назви документів — посилання, але в чорнилі, а не в
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
    @Published var password = ""
    @Published var revealed = false
    /// «Мені вже є 18»: знята, доки людина не поставить сама.
    @Published var adult = false

    var emailValid: Bool { AccountRules.shared.isEmail(value: email) }
    var canSubmit: Bool { emailValid && AccountRules.shared.isPassword(value: password) }
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

/// Supabase Auth шле код не частіше за раз на хвилину.
private let codeResendDelay: TimeInterval = 60

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
