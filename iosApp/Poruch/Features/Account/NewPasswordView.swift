import SwiftUI
import Shared

/// Новий пароль після листа відновлення: один крок у шторці, та сама шапка, що на вході.
/// Шторка живе, поки `passwordRecovery`; профіль лишається запасним шляхом, якщо її змахнути.
struct NewPasswordView: View {
    @EnvironmentObject var model: AppModel
    @State private var password = ""
    @State private var confirm = ""
    @State private var revealed = false

    /// Помилку показуємо лише коли в повторі вже щось є: порожнє поле — ще не помилка.
    private var mismatch: Bool { !confirm.isEmpty && confirm != password }
    private var canSave: Bool { AccountRules.shared.isPassword(value: password) && confirm == password }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) {
                VStack(alignment: .leading, spacing: Space.md) {
                    Text(Copy.new_password).font(PoruchFont.brandTitle1).kerning(-0.4).foregroundStyle(Palette.ink)
                    Text(Copy.new_password_subtitle)
                        .font(PoruchFont.bodyText).foregroundStyle(Palette.inkSecondary)
                }
                .padding(.horizontal, Space.page).padding(.vertical, Space.xxl)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(heroGradient)
                VStack(alignment: .leading, spacing: Space.lg) {
                    LabelledField(label: Copy.password_label, text: $password, hint: Copy.password_hint, secure: !revealed) {
                        PasswordRevealToggle(revealed: $revealed)
                    }
                    .textContentType(.newPassword)
                    // Один перемикач на обидва поля: показує або ховає пароль разом із повтором.
                    LabelledField(label: Copy.password_confirm_label, text: $confirm, secure: !revealed)
                        .textContentType(.newPassword)
                    if mismatch {
                        Text(Copy.err_passwords_mismatch).font(PoruchFont.caption).foregroundStyle(Palette.danger)
                    }
                    PrimaryButton(title: Copy.save_password, loading: model.state?.mutating == true, enabled: canSave) {
                        model.app.updatePassword(password: password)
                    }
                }.padding(.horizontal, Space.page)
            }.padding(.bottom, Space.section)
        }
        .background(Palette.canvas)
        // Банер кореня лишається під шторкою: слабкий пароль чи відмову показуємо тут.
        .notice(model.state?.notice?.presented) { model.app.clearNotice() }
    }
}
