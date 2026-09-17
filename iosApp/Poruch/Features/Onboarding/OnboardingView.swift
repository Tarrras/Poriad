import SwiftUI
import Shared

/// Онбординг: три питання, кожне одним рішенням без скролу, «Пропустити» на кожному кроці.
/// Відповіді пишуться в стор усі разом наприкінці; потік завершує стор.
struct OnboardingView: View {
    @EnvironmentObject var model: AppModel
    @State private var step = OnboardingStep.welcome
    @State private var interests: [String] = []
    @State private var times: [String] = []
    @State private var crowd = Crowd.shared.ANY
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            topRow
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    switch step {
                    case .welcome: welcome
                    case .interests: interestsStep
                    case .times: timesStep
                    case .crowd: crowdStep
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, step == .welcome ? Space.section : Space.lg)
            }
            VStack(spacing: Space.sm) {
                PrimaryButton(title: step.actionLabel) { advance() }
                Button("Пропустити") { model.app.skipOnboarding() }
                    .font(PoruchFont.button).foregroundStyle(Palette.inkSecondary)
                    .padding(.vertical, Space.sm)
            }.padding(.vertical, Space.lg)
        }
        .padding(.horizontal, Space.page)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(heroGradient.ignoresSafeArea())
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: step)
        .onAppear {
            // Відкрито з профілю: починаємо з минулих відповідей.
            guard let taste = model.state?.taste else { return }
            interests = taste.interests
            times = taste.times
            crowd = taste.crowd
        }
    }

    /// Де ви і як назад. Лічильник кроків з'являється, коли є що рахувати.
    private var topRow: some View {
        HStack(spacing: Space.md) {
            if step != .welcome {
                IconPill(symbol: "chevron.left", label: "Назад", size: 40) { step = step.previous }
                Text("Крок \(step.rawValue) з \(OnboardingStep.allCases.count - 1)")
                    .font(PoruchFont.label).foregroundStyle(Palette.inkSecondary)
            }
            Spacer(minLength: 0)
            stepDots
        }.frame(height: 56)
    }

    /// Чотири крапки замість смуги прогресу: смуга обіцяє анкету.
    private var stepDots: some View {
        HStack(spacing: Space.xs) {
            ForEach(OnboardingStep.allCases, id: \.self) { dot in
                Capsule()
                    .fill(dot == step ? Palette.brand : Palette.hairline)
                    .frame(width: dot == step ? 18 : 6, height: 6)
            }
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            PoruchIcon(glyph: PoruchIcons.sparkle, size: 32).foregroundStyle(Palette.brand)
                .frame(width: 72, height: 72)
                .background(Palette.brandContainer, in: RoundedRectangle(cornerRadius: Corner.lg, style: .continuous))
            Text("Знайомимось").font(PoruchFont.display).displayTracking().foregroundStyle(Palette.ink)
            Text("Три питання — і «Поряд» показуватиме спершу те, що вам підходить. Відповіді лишаються на цьому пристрої, змінити їх можна будь-коли у профілі.")
                .font(PoruchFont.lead).foregroundStyle(Palette.inkSecondary)
        }
    }

    private var interestsStep: some View {
        question("Що вам цікаво?", "Оберіть будь-скільки категорій — події з них будуть вище у списках.") {
            FlexibleRow(items: categories.map(\.0)) { category in
                CategoryTile(category: category, selected: interests.contains(category)) {
                    interests = interests.toggling(category)
                }
            }
        }
    }

    private var timesStep: some View {
        question("Коли вам зручно?", "Підіймемо вище те, на що ви встигаєте.") {
            VStack(spacing: Space.sm) {
                ForEach(timeSlots, id: \.slot) { option in
                    ChoiceRow(title: option.title, hint: option.hint, selected: times.contains(option.slot), multiple: true) {
                        times = times.toggling(option.slot)
                    }
                }
            }
        }
    }

    private var crowdStep: some View {
        question("Яка компанія?", "Це про розмір події, а не про людей на ній.") {
            VStack(spacing: Space.sm) {
                ForEach(crowdOptions, id: \.value) { option in
                    ChoiceRow(title: option.title, hint: option.hint, selected: crowd == option.value, multiple: false) {
                        crowd = option.value
                    }
                }
            }
        }
    }

    @ViewBuilder private func question<Content: View>(
        _ title: String, _ hint: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(title).font(PoruchFont.title1).titleTracking().foregroundStyle(Palette.ink)
                Text(hint).font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary)
            }
            content()
        }
    }

    private func advance() {
        guard step == .crowd else {
            step = step.next
            return
        }
        model.app.saveTaste(interests: interests, times: times, crowd: crowd)
    }
}

/// Кроки онбордингу. Лише те, що читає ранжування: кожен зайвий екран — привід піти.
private enum OnboardingStep: Int, CaseIterable {
    case welcome, interests, times, crowd

    var next: OnboardingStep { OnboardingStep(rawValue: rawValue + 1) ?? .crowd }
    var previous: OnboardingStep { OnboardingStep(rawValue: rawValue - 1) ?? .welcome }
    var actionLabel: String {
        switch self {
        case .welcome: "Почати"
        case .crowd: "Готово"
        default: "Далі"
        }
    }
}

/// Одна відповідь на картці. Квадрат — можна кілька, коло — рівно одну.
private struct ChoiceRow: View {
    let title: String
    let hint: String
    let selected: Bool
    let multiple: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(PoruchFont.title3).foregroundStyle(Palette.ink)
                    Text(hint).font(PoruchFont.caption).foregroundStyle(Palette.inkSecondary)
                }
                Spacer(minLength: 0)
                mark
            }
            .padding(Space.lg).frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(radius: Corner.md)
            .overlay(
                RoundedRectangle(cornerRadius: Corner.md, style: .continuous)
                    .strokeBorder(Palette.ink, lineWidth: selected ? 2 : 0)
            )
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var mark: some View {
        let shape = RoundedRectangle(cornerRadius: multiple ? Corner.xs : 12, style: .continuous)
        ZStack {
            shape.fill(selected ? Palette.brand : Palette.surfaceMuted)
            if selected {
                Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.onBrand)
            }
        }.frame(width: 24, height: 24)
    }
}

/// Переносить плитки категорій на стільки рядків, скільки треба; на телефоні по чотири.
private struct FlexibleRow<Content: View>: View {
    let items: [String]
    @ViewBuilder let content: (String) -> Content
    private let perRow = 4

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            ForEach(Array(stride(from: 0, to: items.count, by: perRow)), id: \.self) { start in
                HStack(spacing: Space.sm) {
                    ForEach(items[start..<min(start + perRow, items.count)], id: \.self) { content($0) }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

/// Слоти зі спільного модуля з підписами, у порядку тижня.
private let timeSlots: [(slot: String, title: String, hint: String)] = [
    (TimeSlot.shared.WEEKDAY_EVENING, "Будні, ввечері", "Після 17:00"),
    (TimeSlot.shared.WEEKEND_DAY, "Вихідні, вдень", "Субота й неділя до 17:00"),
    (TimeSlot.shared.WEEKEND_EVENING, "Вихідні, ввечері", "Субота й неділя після 17:00"),
    (TimeSlot.shared.WEEKDAY_DAY, "Будні, вдень", "До 17:00")
]

private let crowdOptions: [(value: String, title: String, hint: String)] = [
    (Crowd.shared.INTIMATE, "Камерна", "До 12 місць"),
    (Crowd.shared.MEDIUM, "Середня", "13–40 місць"),
    (Crowd.shared.ANY, "Будь-яка", "Розмір не має значення")
]

private extension Array where Element == String {
    func toggling(_ value: String) -> [String] { contains(value) ? filter { $0 != value } : self + [value] }
}
