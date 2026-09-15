import SwiftUI
import Shared

/// Екран акаунта: хто ви, що вам цікаво, як з вами зв'язатися.
struct ProfileView: View {
    @EnvironmentObject var model: AppModel
    @State private var newPassword = ""
    @State private var revealed = false
    @State private var showAuth = false
    /// Висота смуги статусу: хедер додає її сам, як на головній.
    @State private var statusBar: CGFloat = Space.xxl
    @State private var birthDate = Calendar.current.date(byAdding: .year, value: -Int(SafetyRules.shared.MIN_SIGNUP_AGE), to: Date()) ?? Date()
    private let latestBirthDate = Calendar.current.date(byAdding: .year, value: -Int(SafetyRules.shared.MIN_SIGNUP_AGE), to: Date()) ?? Date()
    private let earliestBirthDate = Calendar.current.date(byAdding: .year, value: -100, to: Date()) ?? Date.distantPast

    private var signedIn: Bool { model.state?.signedIn == true }
    private var recovering: Bool { model.state?.passwordRecovery == true }

    var body: some View {
        // Як у HomeView: стрічка під смугу статусу, хедер додає відступ.
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) {
                header
                VStack(alignment: .leading, spacing: Space.xxl) {
                    if recovering { recovery }
                    if !signedIn && !recovering { signInPrompt }
                    if model.state?.needsAgeDeclaration == true { ageDeclaration }
                    taste
                    if signedIn { account }
                    if !(model.state?.blocked ?? []).isEmpty { blocked }
                    about
                }.padding(.horizontal, Space.page)
            }.padding(.bottom, Space.section)
        }
        .background(Palette.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showAuth) { NavigationStack { AuthView() } }
        .ignoresSafeArea(edges: .top)
        .tracksStatusBarInset($statusBar)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            PoruchIcon(glyph: PoruchIcons.person, size: 32).foregroundStyle(Palette.onBrandContainer)
                .frame(width: 64, height: 64).background(Palette.brandContainer, in: Circle())
            Text(signedIn ? "Ви з нами" : "Ваші люди — поруч").font(PoruchFont.title1).titleTracking().foregroundStyle(Palette.ink)
            Text(signedIn
                 ? "Ваші створені, збережені та заплановані події — у вкладці «Мої події»."
                 : "Увійдіть, щоб зберігати цікаве, приєднуватись і створювати власні зустрічі.")
                .font(PoruchFont.bodyText).foregroundStyle(Palette.inkSecondary)
        }
        .padding(.horizontal, Space.page).padding(.vertical, Space.xxl)
        .padding(.top, statusBar)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(heroGradient)
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
            DatePicker("", selection: $birthDate, in: earliestBirthDate...latestBirthDate, displayedComponents: .date)
                .datePickerStyle(.compact).labelsHidden().tint(Palette.brand)
            PrimaryButton(title: "Вказати дату") { model.app.declareBirthDate(birthDate: isoDay(birthDate)) }
        }
        .padding(Space.lg).frame(maxWidth: .infinity, alignment: .leading).cardSurface()
    }

    /// Блок, який не можна скасувати, не використовуватимуть: список з іменами.
    private var blocked: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader(title: "Заблоковані")
            ForEach(model.state?.blocked ?? [], id: \.userId) { person in
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

    /// Відповіді онбордингу належать пристрою, тож секція є і в гостя.
    private var taste: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader(title: "Ваші інтереси")
            FlexibleChips(
                items: categories.map { ($0.0, $0.1, $0.0) },
                isSelected: { model.state?.interests.contains($0) == true }
            ) { model.app.toggleInterest(category: $0) }
            Button { model.app.restartOnboarding() } label: {
                HStack(spacing: Space.md) {
                    PoruchIcon(glyph: PoruchIcons.sparkle, size: 20).foregroundStyle(Palette.brand)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Налаштувати рекомендації").font(PoruchFont.cardName).foregroundStyle(Palette.ink)
                        Text("Пройти опитування ще раз").font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.inkTertiary)
                }
                .padding(Space.lg).frame(maxWidth: .infinity, alignment: .leading).cardSurface()
            }.buttonStyle(PressableStyle())
        }
    }

    private var account: some View {
        VStack(alignment: .leading, spacing: Space.xxl) {
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
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Toggle(isOn: enabled) {
                Text("Нагадувати за годину до події").font(PoruchFont.bodyText).foregroundStyle(Palette.ink)
            }
            .tint(Palette.brand)
            Text(denied ? "Дозвольте сповіщення в налаштуваннях iOS." : "Локальне нагадування приблизно за годину до початку.")
                .font(PoruchFont.caption).foregroundStyle(denied ? Palette.danger : Palette.inkTertiary)
        }.padding(Space.lg).cardSurface()
    }
}
