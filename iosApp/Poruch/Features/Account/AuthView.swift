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
                .font(PoruchFont.title1).foregroundStyle(Palette.ink)
            Text(form.register
                 ? "Кілька секунд — і ви зможете приєднуватись до подій та створювати власні."
                 : "Події можна переглядати без входу. Для участі потрібен профіль.")
                .font(PoruchFont.bodyText).foregroundStyle(Palette.inkSecondary)
        }
        .padding(.horizontal, Space.page).padding(.vertical, Space.xxl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.canvasTint)
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            if form.register {
                LabelledField(label: "Ваше ім’я", text: $form.name, placeholder: "Як до вас звертатися")
                    .textContentType(.name)
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

    var emailValid: Bool { AccountRules.shared.isEmail(value: email) }
    var canSubmit: Bool {
        emailValid && AccountRules.shared.isPassword(value: password) &&
            (!register || AccountRules.shared.isName(value: name))
    }

    /// The password never survives a mode switch: it belongs to the attempt, not the screen.
    func toggleMode() { register.toggle(); password = "" }

    func submit(with app: PoruchApp) {
        if register { app.signUp(email: email, password: password, name: name) }
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
