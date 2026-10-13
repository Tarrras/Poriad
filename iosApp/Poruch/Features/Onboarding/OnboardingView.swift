import SwiftUI
import Shared

/// Онбординг: три питання, кожне одним рішенням без скролу, «Пропустити» на кожному кроці.
/// Відповіді пишуться в стор усі разом наприкінці; потік завершує стор.
struct OnboardingView: View {
    @EnvironmentObject var model: AppModel
    @State private var step = OnboardingStep.welcome
    @State private var interests: [EventCategory] = []
    @State private var times: [TimeSlot] = []
    @State private var crowd = Crowd.any
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
                .padding(.top, Space.lg)
            }
            // Одна дія внизу: «Пропустити» живе вгорі праворуч і не сперечається з нею.
            PrimaryButton(title: step.actionLabel) { advance() }.padding(.vertical, Space.lg)
        }
        .padding(.horizontal, Space.page)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.canvas.ignoresSafeArea())
        .motion(value: step)
        .onAppear {
            // Відкрито з профілю: починаємо з минулих відповідей.
            guard let taste = model.state?.taste else { return }
            interests = taste.interests
            times = taste.times
            crowd = taste.crowd
        }
    }

    /// Назад, прогрес трьома сегментами і «Пропустити». На вітанні прогресу ще нема чого показувати.
    private var topRow: some View {
        HStack(spacing: Space.md) {
            if step != .welcome {
                IconPill(symbol: "chevron.left", label: Copy.back, size: 40) { step = step.previous }
                HStack(spacing: Space.xs) {
                    ForEach(1..<OnboardingStep.allCases.count, id: \.self) { index in
                        Capsule().fill(index <= step.rawValue ? Palette.brand : Palette.brandContainer).frame(height: 4)
                    }
                }
                .accessibilityElement()
                .accessibilityLabel(Copy.onboarding_step("\(step.rawValue)", "\(OnboardingStep.allCases.count - 1)"))
            } else {
                Spacer(minLength: 0)
            }
            Button(Copy.rate_skip) { model.app.skipOnboarding() }
                .font(PoruchFont.button).foregroundStyle(Palette.inkSecondary)
                .frame(minHeight: 44)
        }.frame(height: 56)
    }

    /// Вітання по центру: мозаїка плиток категорій замість одного значка — одразу видно, про що застосунок.
    private var welcome: some View {
        VStack(spacing: Space.xl) {
            HStack(alignment: .center, spacing: Space.sm) {
                mosaicTile(.music, 52).offset(y: 18)
                mosaicTile(.food, 68).offset(y: -6)
                mosaicTile(.social, 96)
                mosaicTile(.outdoors, 68).offset(y: -6)
                mosaicTile(.games, 52).offset(y: 18)
            }
            .padding(.top, Space.section).padding(.bottom, Space.lg)
            .decorative()
            VStack(spacing: Space.md) {
                Text(Copy.onboarding_welcome_title).font(PoruchFont.serifDisplay).kerning(-0.5).foregroundStyle(Palette.ink)
                Text(Copy.onboarding_welcome_body)
                    .font(PoruchFont.lead).foregroundStyle(Palette.inkSecondary).multilineTextAlignment(.center)
            }
        }.frame(maxWidth: .infinity)
    }

    private func mosaicTile(_ category: EventCategory, _ size: CGFloat) -> some View {
        PoruchIcon(glyph: categoryGlyph(category), size: size * 0.42).foregroundStyle(categoryInk(category))
            .frame(width: size, height: size)
            .background(categoryGradient(category), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }

    private var interestsStep: some View {
        question(Copy.onboarding_interests_title, Copy.onboarding_interests_hint) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.sm), count: 3), spacing: Space.sm) {
                ForEach(categories, id: \.0) { entry in
                    CategoryCard(category: entry.0, selected: interests.contains(entry.0)) {
                        interests = interests.toggling(entry.0)
                    }
                }
            }
        }
    }

    private var timesStep: some View {
        question(Copy.onboarding_times_title, Copy.onboarding_times_hint) {
            GroupedRows {
                ForEach(Array(timeSlots.enumerated()), id: \.element.slot) { index, option in
                    ChoiceRow(title: option.title, hint: option.hint, selected: times.contains(option.slot), multiple: true) {
                        times = times.toggling(option.slot)
                    }
                    if index < timeSlots.count - 1 { Divider().overlay(Palette.hairline).padding(.leading, Space.lg) }
                }
            }
        }
    }

    private var crowdStep: some View {
        question(Copy.onboarding_crowd_title, Copy.onboarding_crowd_hint) {
            GroupedRows {
                ForEach(Array(crowdOptions.enumerated()), id: \.element.value) { index, option in
                    ChoiceRow(title: option.title, hint: option.hint, selected: crowd == option.value, multiple: false) {
                        crowd = option.value
                    }
                    if index < crowdOptions.count - 1 { Divider().overlay(Palette.hairline).padding(.leading, Space.lg) }
                }
            }
        }
    }

    @ViewBuilder private func question<Content: View>(
        _ title: String, _ hint: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(title).font(PoruchFont.serifDisplay).kerning(-0.5).foregroundStyle(Palette.ink)
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
        case .welcome: Copy.onboarding_start
        case .crowd: Copy.apply
        default: Copy.next
        }
    }
}

/// Одна відповідь рядком групового списку. Квадрат — можна кілька, коло — рівно одну.
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
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(pressedScale: 1))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var mark: some View {
        // Радіус явний, не токен: `Corner.xs` = 12 робив із квадрата 24 pt коло, і «кілька» не відрізнялось від «одну».
        let shape = RoundedRectangle(cornerRadius: multiple ? 7 : 12, style: .continuous)
        ZStack {
            shape.fill(selected ? Palette.brand : Palette.surfaceMuted)
            if selected {
                PoruchIcon(glyph: PoruchIcons.check, size: 15).foregroundStyle(Palette.onBrand)
            }
        }.frame(width: 24, height: 24)
    }
}

/// Слоти зі спільного модуля з підписами, у порядку тижня.
private let timeSlots: [(slot: TimeSlot, title: String, hint: String)] = [
    (.weekdayEvening, Copy.slot_weekday_evening, Copy.slot_weekday_evening_hint),
    (.weekendDay, Copy.slot_weekend_day, Copy.slot_weekend_day_hint),
    (.weekendEvening, Copy.slot_weekend_evening, Copy.slot_weekend_evening_hint),
    (.weekdayDay, Copy.slot_weekday_day, Copy.slot_weekday_day_hint)
]

private let crowdOptions: [(value: Crowd, title: String, hint: String)] = [
    (.intimate, Copy.crowd_intimate, Copy.crowd_intimate_hint),
    (.medium, Copy.crowd_medium, Copy.crowd_medium_hint),
    (.any, Copy.crowd_any, Copy.crowd_any_hint)
]

private extension Array where Element: Equatable {
    func toggling(_ value: Element) -> [Element] { contains(value) ? filter { $0 != value } : self + [value] }
}
