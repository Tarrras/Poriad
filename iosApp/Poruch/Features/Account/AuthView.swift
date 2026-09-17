import SwiftUI
import Shared

/// Вхід і реєстрація: один екран, два режими. Реєстрація — друга половина, а не примітка.
struct AuthView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = AuthFormModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) {
                header
                if let email = model.state?.awaitingConfirmation { confirmation(email) } else { fields }
            }.padding(.bottom, Space.section)
        }
        .background(Palette.canvas)
        .toolbar(.hidden, for: .navigationBar)
        // Екран живе в шиті, а банер кореня лишається під ним: помилки й відповіді показуємо тут.
        .notice(model.state?.notice?.presented) { model.app.clearNotice() }
        .onChange(of: model.state?.userId) { _, userId in
            if userId != nil && model.state?.passwordRecovery != true { dismiss() }
        }
        .onDisappear { model.app.dismissConfirmationStep() }
    }

    private var confirming: Bool { model.state?.awaitingConfirmation != nil }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            ScrimButton(symbol: "chevron.left", label: "Назад") { dismiss() }
            Text(confirming ? "Перевірте пошту" : form.register ? "Створити профіль" : "З поверненням")
                .font(PoruchFont.title1).titleTracking().foregroundStyle(Palette.ink)
            Text(confirming
                 ? "Лишився один крок — підтвердити адресу."
                 : form.register
                 ? "Кілька секунд — і ви зможете приєднуватись до подій та створювати власні."
                 : "Події можна переглядати без входу. Для участі потрібен профіль.")
                .font(PoruchFont.bodyText).foregroundStyle(Palette.inkSecondary)
        }
        .padding(.horizontal, Space.page).padding(.vertical, Space.xxl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(heroGradient)
    }

    /// Наступний крок після реєстрації без сесії: куди пішов лист і що з ним робити. Той самий
    /// екран, а не банер: людина має побачити адресу й зрозуміти, що профіль ще не працює.
    private func confirmation(_ email: String) -> some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            VStack(alignment: .leading, spacing: Space.md) {
                Image(systemName: "envelope")
                    .font(.system(size: 20, weight: .semibold)).foregroundStyle(Palette.onBrandContainer)
                    .frame(width: 48, height: 48).background(Palette.brandContainer, in: Circle())
                Text("Ми надіслали лист на \(email). Відкрийте посилання в ньому — і профіль готовий, застосунок відкриється сам.")
                    .font(PoruchFont.bodyText).foregroundStyle(Palette.ink)
                Text("Немає листа? Зачекайте хвилину й загляньте в «Спам».")
                    .font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary)
            }
            .padding(Space.xl).frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(radius: Corner.md, elevation: Elevation.card)
            PrimaryButton(title: "Відкрити пошту", symbol: "envelope") {
                if let url = URL(string: "message://") { UIApplication.shared.open(url) }
            }
            SecondaryButton(title: "Уже підтвердили? Увійти") {
                // Лист підтверджено: пошта вже в полі, лишається пароль.
                model.app.dismissConfirmationStep()
                form.register = false
                form.password = ""
            }
            .frame(maxWidth: .infinity)
        }.padding(.horizontal, Space.page)
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            if form.register {
                LabelledField(label: "Ваше ім’я", text: $form.name, placeholder: "Як до вас звертатися")
                    .textContentType(.name)
                // Питаємо раз, при реєстрації, і нікому не показуємо: на це спираються вікові межі й модерація.
                VStack(alignment: .leading, spacing: Space.sm) {
                    Text("ДАТА НАРОДЖЕННЯ").font(PoruchFont.overline).kerning(1.2).foregroundStyle(Palette.inkTertiary)
                    DatePicker(
                        "", selection: $form.birthDate, in: form.earliestBirthDate...form.latestBirthDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact).labelsHidden().tint(Palette.brand)
                    Text("«Поряд» — застосунок для повнолітніх. Дату видно лише вам.")
                        .font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary)
                }
            }
            LabelledField(label: "Електронна пошта", text: $form.email, placeholder: "you@example.com")
                .textContentType(.emailAddress).keyboardType(.emailAddress)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            LabelledField(label: "Пароль", text: $form.password, hint: "Щонайменше 8 символів", secure: !form.revealed) {
                PasswordRevealToggle(revealed: $form.revealed)
            }
            .textContentType(form.register ? .newPassword : .password)
            // Під час запиту кнопка лишається кольоровою зі спінером: сама блокує дотик, поки `loading`.
            PrimaryButton(
                title: form.register ? "Зареєструватися" : "Увійти",
                loading: model.state?.mutating == true,
                enabled: form.canSubmit
            ) { form.submit(with: model.app) }
            if form.register { consent }
            Button("Забули пароль?") { model.app.requestPasswordReset(email: form.email) }
                .font(PoruchFont.label).foregroundStyle(Palette.inkSecondary)
                .disabled(!form.emailValid || model.state?.mutating == true)
            HStack(spacing: Space.md) {
                Rectangle().fill(Palette.hairline).frame(height: 1)
                Text(form.register ? "Уже зареєстровані?" : "Ще немає профілю?")
                    .font(PoruchFont.caption).foregroundStyle(Palette.inkTertiary).fixedSize()
                Rectangle().fill(Palette.hairline).frame(height: 1)
            }
            .padding(.top, Space.xs)
            SecondaryButton(title: form.register ? "Увійти" : "Створити профіль") { form.toggleMode() }
                .frame(maxWidth: .infinity)
        }.padding(.horizontal, Space.page)
    }

    /// Згода під кнопкою реєстрації: назви документів — посилання, але в чорнилі, а не в
    /// системному синьому, щоб рядок лишався підписом, а не закликом. Адреси спільні з Android.
    private var consent: some View {
        var text = AttributedString("Реєструючись, ви погоджуєтесь з ")
        text.append(legalLink("Умовами користування", LegalLinks.shared.TERMS))
        text.append(AttributedString(" та "))
        text.append(legalLink("Політикою конфіденційності", LegalLinks.shared.PRIVACY))
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
    @Published var register = false
    /// Відкривається на дні народження того, кому щойно 18: найближча правдоподібна відповідь.
    @Published var birthDate = AuthFormModel.defaultBirthDate

    /// Мінімум задає сам контрол; база перевірить ще раз.
    let latestBirthDate = AuthFormModel.defaultBirthDate
    let earliestBirthDate = Calendar.current.date(byAdding: .year, value: -100, to: Date()) ?? Date.distantPast

    private static var defaultBirthDate: Date {
        Calendar.current.date(byAdding: .year, value: -Int(SafetyRules.shared.MIN_SIGNUP_AGE), to: Date()) ?? Date()
    }

    var emailValid: Bool { AccountRules.shared.isEmail(value: email) }
    var canSubmit: Bool {
        emailValid && AccountRules.shared.isPassword(value: password) &&
            (!register || (AccountRules.shared.isName(value: name) && birthDate <= latestBirthDate))
    }

    /// Пароль не переживає зміну режиму.
    func toggleMode() { register.toggle(); password = "" }

    func submit(with app: PoruchApp) {
        if register { app.signUp(email: email, password: password, name: name, birthDate: isoDay(birthDate)) }
        else { app.signIn(email: email, password: password) }
    }
}

struct PasswordRevealToggle: View {
    @Binding var revealed: Bool
    var body: some View {
        Button { revealed.toggle() } label: {
            Image(systemName: revealed ? "eye.slash" : "eye")
                .font(.system(size: 15)).foregroundStyle(Palette.inkSecondary)
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(revealed ? "Приховати пароль" : "Показати пароль")
    }
}

/// Дата народження їде як календарний день, без часу й поясу.
func isoDay(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
}
