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
            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.xl) {
                        switch step {
                        case .welcome: welcome
                        case .interests: interestsStep
                        case .times: timesStep
                        case .crowd: crowdStep
                        }
                    }
                    .padding(.top, Space.lg)
                    // Вітання — по центру вільного місця, питання — від верху.
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: step == .welcome ? .center : .topLeading)
                }
                .scrollBounceBehavior(.basedOnSize)
                // Нижче є ще вміст (великий шрифт, малий екран) — індикатор блимає, щоб це було видно.
                .scrollIndicatorsFlash(trigger: step)
            }
            // Одна дія внизу: «Пропустити» живе вгорі праворуч і не сперечається з нею.
            PrimaryButton(title: step.actionLabel) { advance() }.padding(.vertical, Space.lg)
        }
        .padding(.horizontal, Space.page)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.canvas.ignoresSafeArea())
        .motion(value: step)
        .onAppear {
            // Відкрито з профілю: починаємо з минулих відповідей і одразу з питань — знайомі вже знайомі.
            guard let taste = model.state?.taste else { return }
            interests = taste.interests
            times = taste.times
            crowd = taste.crowd
            if !interests.isEmpty || !times.isEmpty || crowd != .any { step = .interests }
        }
    }

    /// Назад, прогрес трьома сегментами і «Пропустити». На вітанні прогресу ще нема чого показувати.
    private var topRow: some View {
        HStack(spacing: Space.md) {
            if step != .welcome {
                IconPill(glyph: PoruchIcons.chevronLeft, label: Copy.back, size: 40) { step = step.previous }
                HStack(spacing: Space.xs) {
                    ForEach(1..<OnboardingStep.allCases.count, id: \.self) { index in
                        Capsule().fill(index <= step.rawValue ? Palette.brand : Palette.inkTertiary.opacity(0.5)).frame(height: 4)
                    }
                }
                .accessibilityElement()
                .accessibilityLabel(Copy.onboarding_step("\(step.rawValue)", "\(OnboardingStep.allCases.count - 1)"))
            } else {
                Spacer(minLength: 0)
            }
            Button(Copy.onboarding_skip) { model.app.skipOnboarding() }
                .font(PoruchFont.button).foregroundStyle(Palette.inkSecondary)
                .frame(minHeight: 44)
                // На великому шрифті стискається прогрес, а не «Пропустити».
                .layoutPriority(1)
        }.frame(height: 56)
    }

    /// Вітання: перший квиток «Поряд» — слоган надруковано, решта ще порожня, корінці фарбують жанри.
    private var welcome: some View {
        VStack(spacing: Space.section) {
            WelcomeTicket()
            VStack(spacing: Space.md) {
                Text(Copy.onboarding_welcome_title).font(PoruchFont.brandTitle2).foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(Copy.onboarding_welcome_body)
                    .font(PoruchFont.lead).foregroundStyle(Palette.inkSecondary).multilineTextAlignment(.center)
            }
        }.frame(maxWidth: .infinity)
    }

    private var interestsStep: some View {
        question(Copy.onboarding_interests_title, Copy.onboarding_interests_hint) {
            // Ті самі плитки й сітка, що в шторці категорій: чотири в ряд — усі одинадцять видно без прокрутки.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: Space.sm)], spacing: Space.lg) {
                ForEach(categories, id: \.0) { entry in
                    CategoryTile(category: entry.0, selected: interests.contains(entry.0)) {
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
                Text(title).font(PoruchFont.brandDisplay).kerning(-0.5).foregroundStyle(Palette.ink)
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
        case .crowd: Copy.onboarding_finish
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
            // Невибране — контуром: тиха заливка вночі зливалась із рядком (1,2:1), і не було видно, що тут щось обирають.
            if selected { shape.fill(Palette.brand) } else { shape.strokeBorder(Palette.inkTertiary, lineWidth: 1.5) }
            if selected {
                PoruchIcon(glyph: PoruchIcons.check, size: 15).foregroundStyle(Palette.onBrand)
            }
        }.frame(width: 24, height: 24)
    }
}

/// Слоти зі спільного модуля з підписами, у порядку тижня: будні, потім вихідні, у кожних — день, потім вечір.
private let timeSlots: [(slot: TimeSlot, title: String, hint: String)] = [
    (.weekdayDay, Copy.slot_weekday_day, Copy.slot_weekday_day_hint),
    (.weekdayEvening, Copy.slot_weekday_evening, Copy.slot_weekday_evening_hint),
    (.weekendDay, Copy.slot_weekend_day, Copy.slot_weekend_day_hint),
    (.weekendEvening, Copy.slot_weekend_evening, Copy.slot_weekend_evening_hint)
]

private let crowdOptions: [(value: Crowd, title: String, hint: String)] = [
    (.intimate, Copy.crowd_intimate, Copy.crowd_intimate_hint),
    (.medium, Copy.crowd_medium, Copy.crowd_medium_hint),
    (.any, Copy.crowd_any, Copy.crowd_any_hint)
]

/// Перший квиток: вертикальний, як «Від людей». Слоган надруковано, нижче — незадруковані рядки: решту допишуть відповіді.
/// Корінець розрізано на п'ять, кожен залитий кольором жанру з його гліфом — видно, про що застосунок.
private struct WelcomeTicket: View {
    private let genres: [EventCategory] = [.music, .food, .social, .outdoors, .games]
    var body: some View {
        Ticket(vertical: true, stubColor: Palette.canvas, stubLength: 64, radius: Corner.lg) {
            VStack(alignment: .leading, spacing: Space.xl) {
                Text(Copy.onboarding_slogan).font(PoruchFont.brandDisplay).kerning(-0.5).foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 6) {
                    Capsule().fill(Palette.hairline).frame(width: 112, height: 6)
                    Capsule().fill(Palette.hairline).frame(width: 68, height: 6)
                }
                .accessibilityHidden(true)
            }
            .padding(Space.xl)
        } stub: {
            HStack(spacing: 2) {
                ForEach(genres, id: \.self) { genre in
                    PoruchIcon(glyph: categoryGlyph(genre), size: 22).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(categoryStub(genre))
                }
            }
            .accessibilityHidden(true)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: 320)
        .accessibilityElement(children: .contain)
    }
}

private extension Array where Element: Equatable {
    func toggling(_ value: Element) -> [Element] { contains(value) ? filter { $0 != value } : self + [value] }
}
