import SwiftUI
import Shared

/// The account screen: who you are, what you follow, and how the app may reach you.
struct ProfileView: View {
    @EnvironmentObject var model: AppModel
    @State private var newPassword = ""
    @State private var revealed = false
    @State private var showAuth = false

    private var signedIn: Bool { model.state?.signedIn == true }
    private var recovering: Bool { model.state?.passwordRecovery == true }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) {
                header
                VStack(alignment: .leading, spacing: Space.xxl) {
                    if recovering { recovery }
                    if signedIn { account } else if !recovering { signInPrompt }
                    about
                }.padding(.horizontal, Space.page)
            }.padding(.bottom, Space.section)
        }
        .background(Palette.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showAuth) { NavigationStack { AuthView() } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            PoruchIcon(glyph: PoruchIcons.person, size: 32).foregroundStyle(Palette.onBrandContainer)
                .frame(width: 64, height: 64).background(Palette.brandContainer, in: Circle())
            Text(signedIn ? "Ви з нами" : "Ваші люди — поруч").font(PoruchFont.title1).foregroundStyle(Palette.ink)
            Text(signedIn
                 ? "Ваші створені, збережені та заплановані події — у вкладці «Мої події»."
                 : "Увійдіть, щоб зберігати цікаве, приєднуватись і створювати власні зустрічі.")
                .font(PoruchFont.bodyText).foregroundStyle(Palette.inkSecondary)
        }
        .padding(.horizontal, Space.page).padding(.vertical, Space.xxl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Palette.canvasTint, Palette.canvas], startPoint: .top, endPoint: .bottom))
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

    private var account: some View {
        VStack(alignment: .leading, spacing: Space.xxl) {
            VStack(alignment: .leading, spacing: Space.md) {
                SectionHeader(title: "Ваші інтереси")
                FlexibleChips(
                    items: categories.map { ($0.0, $0.1, $0.0) },
                    isSelected: { model.state?.interests.contains($0) == true }
                ) { model.app.toggleInterest(category: $0) }
            }
            VStack(alignment: .leading, spacing: Space.md) {
                SectionHeader(title: "Налаштування")
                ReminderPreference()
            }
            SecondaryButton(title: "Вийти з облікового запису", symbol: "rectangle.portrait.and.arrow.right", tone: Palette.danger) {
                model.app.signOut()
            }
        }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader(title: "Про застосунок")
            Text("«Поруч» — події та люди у вашому місті. Мапа: MapLibre та OpenFreeMap.")
                .font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary)
        }
    }
}

/// The reminders switch, with its own permission dance. It reads the plans from the store itself
/// rather than having them threaded through a settings list that has nothing else to do with events.
struct ReminderPreference: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("poruch.reminders") private var enabled = false
    @State private var denied = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Toggle(isOn: $enabled) {
                Text("Нагадувати за годину до події").font(PoruchFont.bodyText).foregroundStyle(Palette.ink)
            }
            .tint(Palette.brand)
            .onChange(of: enabled) { _, isOn in
                guard isOn else {
                    if let state = model.state { model.reminders.reconcile(state) }
                    return
                }
                model.reminders.request { granted in
                    DispatchQueue.main.async {
                        enabled = granted; denied = !granted; model.app.loadMyEvents()
                    }
                }
            }
            Text(denied ? "Дозвольте сповіщення в налаштуваннях iOS." : "Локальне нагадування приблизно за годину до початку.")
                .font(PoruchFont.caption).foregroundStyle(denied ? Palette.danger : Palette.inkTertiary)
        }.padding(Space.lg).cardSurface()
    }
}
