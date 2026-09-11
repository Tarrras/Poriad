import SwiftUI
import Shared

/// Sign-in and registration, one screen with two modes. Registration is the other half of it, not
/// a footnote: everyone arriving without an account has to reach it.
struct AuthView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = AuthFormModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) {
                header
                fields
            }.padding(.bottom, Space.section)
        }
        .background(Palette.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: model.state?.userId) { _, userId in
            if userId != nil && model.state?.passwordRecovery != true { dismiss() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            ScrimButton(symbol: "chevron.left", label: "Назад") { dismiss() }
            Text(form.register ? "Створити профіль" : "З поверненням")
                .font(PoruchFont.title1).titleTracking().foregroundStyle(Palette.ink)
            Text(form.register
                 ? "Кілька секунд — і ви зможете приєднуватись до подій та створювати власні."
                 : "Події можна переглядати без входу. Для участі потрібен профіль.")
                .font(PoruchFont.bodyText).foregroundStyle(Palette.inkSecondary)
        }
        .padding(.horizontal, Space.page).padding(.vertical, Space.xxl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(heroGradient)
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            if form.register {
                LabelledField(label: "Ваше ім’я", text: $form.name, placeholder: "Як до вас звертатися")
                    .textContentType(.name)
                // Asked once, at sign-up, and shown to nobody else: it is what an age limit on an
                // event rests on, and what a moderation decision later refers back to.
                VStack(alignment: .leading, spacing: Space.sm) {
                    Text("ДАТА НАРОДЖЕННЯ").font(PoruchFont.overline).kerning(1.2).foregroundStyle(Palette.inkTertiary)
                    DatePicker(
                        "", selection: $form.birthDate, in: form.earliestBirthDate...form.latestBirthDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact).labelsHidden().tint(Palette.brand)
                    Text("«Поруч» — застосунок для повнолітніх. Дату видно лише вам.")
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
            PrimaryButton(
                title: form.register ? "Зареєструватися" : "Увійти",
                loading: model.state?.mutating == true,
                enabled: form.canSubmit && model.state?.mutating != true
            ) { form.submit(with: model.app) }
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
}

/// The form's own state, with the same validity rules the shared module enforces.
@MainActor final class AuthFormModel: ObservableObject {
    @Published var email = ""
    @Published var name = ""
    @Published var password = ""
    @Published var revealed = false
    @Published var register = false
    /// Opens on the day somebody who just turned eighteen was born: the nearest plausible answer.
    @Published var birthDate = AuthFormModel.defaultBirthDate

    /// The floor is stated by the control itself; the database checks it again on sign-up.
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

    /// The password never survives a mode switch: it belongs to the attempt, not the screen.
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

/// A birth date travels as a plain calendar day, without a clock or a zone attached to it.
func isoDay(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
}
