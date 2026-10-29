import SwiftUI
import Shared

/// Онбординг: питання, «Пропустити» на кожному кроці. Відповіді пишуться в стор усі разом наприкінці, артисти й райони —
/// підписками там же; потік завершує стор.
struct OnboardingView: View {
    @EnvironmentObject var model: AppModel
    @State private var step = OnboardingStep.welcome
    @State private var interests: [EventCategory] = []
    @State private var times: [TimeSlot] = []
    @State private var crowd = Crowd.any
    /// Обрані на кроці «За ким стежити?»: підписки ставимо разом з рештою відповідей, на «Готово».
    @State private var artists: [String: PopularArtist] = [:]
    /// Райони кроку «Де ви буваєте?»: у «Мої місця» — теж на «Готово».
    @State private var places: Set<Int64> = []
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
                        case .artists: artistsStep
                        case .places: placesStep
                        }
                    }
                    .padding(.top, Space.lg)
                    // Вітання — по центру вільного місця, питання — від верху.
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: step == .welcome ? .center : .topLeading)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
                // Нижче є ще вміст (великий шрифт, малий екран) — індикатор блимає, щоб це було видно.
                .scrollIndicatorsFlash(trigger: step)
            }
            // Одна дія внизу: «Пропустити» живе вгорі праворуч і не сперечається з нею.
            PrimaryButton(title: actionLabel) { advance() }.padding(.vertical, Space.lg)
        }
        .padding(.horizontal, Space.page)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.canvas.ignoresSafeArea())
        .motion(value: step)
        // Місто ще не відоме (геолокацію питаємо після туру), тож артисти — ті, хто гастролює країною.
        .task { model.app.loadPopularArtists(everywhere: true) }
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
                IconPill(glyph: PoruchIcons.chevronLeft, label: Copy.back, size: 40) {
                    step = steps.last { $0.rawValue < step.rawValue } ?? .welcome
                }
                let position = steps.firstIndex(of: step) ?? 0
                HStack(spacing: Space.xs) {
                    ForEach(1..<steps.count, id: \.self) { index in
                        Capsule().fill(index <= position ? Palette.brand : Palette.inkTertiary.opacity(0.5)).frame(height: 4)
                    }
                }
                .accessibilityElement()
                .accessibilityLabel(Copy.onboarding_step("\(position)", "\(steps.count - 1)"))
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

    /// Артисти, що їдуть найбільшою кількістю міст: підписка тут — привід повернутись, коли в них з'являться дати.
    private var artistsStep: some View {
        question(Copy.radar_ask_title, Copy.onboarding_artists_hint) {
            PopularArtistChips(picked: $artists, dates: false)
        }
    }

    /// Райони міста, а не місцевості: адміністративних кілька, і їх знають на ім'я.
    private var districts: [District] {
        (model.state?.city.districts ?? []).filter { !$0.isLocality }.sorted { $0.name < $1.name }
    }

    /// «Де ви буваєте?»: райони чипами, вибір кількох. Ті, за якими вже стежать (онбординг з профілю), позначені й тут
    /// не знімаються, як артисти.
    private var placesStep: some View {
        let followed = model.root.followedDistricts
        return question(Copy.onboarding_places_title, Copy.onboarding_places_hint) {
            VStack(alignment: .leading, spacing: Space.sm) {
                // Місто ще може бути типовим (геолокацію питаємо після туру): назва каже, чиї це райони.
                GroupLabel(title: model.state?.city.name ?? "")
                FlowLayout(spacing: Space.sm) {
                    ForEach(districts, id: \.id) { district in
                        let on = followed.contains(district.id)
                        RadarChip(name: district.shortName, on: on || places.contains(district.id)) {
                            places = places.symmetricDifference([district.id])
                        }
                        .disabled(on)
                    }
                }
            }
        }
    }

    /// Кроки, які є: без артистів (збій, порожньо) чи районів міста відповідного кроку нема.
    private var steps: [OnboardingStep] {
        OnboardingStep.allCases.filter {
            switch $0 {
            case .artists: model.state?.popularArtists?.isEmpty != true
            case .places: !districts.isEmpty
            default: true
            }
        }
    }

    private var actionLabel: String {
        if step == .artists && !artists.isEmpty { return Copy.radar_picker_follow("\(artists.count)") }
        if step == .places && !places.isEmpty { return Copy.onboarding_places_follow(places.count) }
        if step == .welcome { return Copy.onboarding_start }
        return step == steps.last ? Copy.onboarding_finish : Copy.next
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
        // Крок без даних (артистів чи районів нема) пропускаємо: останнім стає попередній.
        if let next = steps.first(where: { $0.rawValue > step.rawValue }) {
            step = next
            return
        }
        if steps.contains(.artists) {
            model.app.followArtists(picked: Array(artists.values), from: "onboarding")
            model.app.radarPickerClosed(shown: Int32(model.state?.popularArtists?.count ?? 0), picked: Int32(artists.count), from: "onboarding")
        }
        // Перемикач: уже обрані з профілю лишаються, бо в `places` їх не буває.
        for district in districts where places.contains(district.id) {
            model.app.toggleDistrictZone(district: district, from: "onboarding")
        }
        model.app.saveTaste(interests: interests, times: times, crowd: crowd)
    }
}

/// Кроки онбордингу: те, що читає ранжування, артисти й райони — привід повернутись. Кожен зайвий екран — привід піти.
private enum OnboardingStep: Int, CaseIterable {
    case welcome, interests, times, crowd, artists, places
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
