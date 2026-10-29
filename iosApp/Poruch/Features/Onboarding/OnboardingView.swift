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
    /// Артисти кроку «Про що сказати?»: підписки ставимо разом з рештою відповідей, на «Готово».
    @State private var artists: [String: PopularArtist] = [:]
    /// Райони того самого кроку: у «Мої місця» — теж на «Готово».
    @State private var places: Set<Int64> = []
    /// Шторка міст з кроку «Про що сказати?»: місто ще типове (геолокацію питаємо після туру), а райони — його.
    @State private var citySearch = false
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
                        case .follow: followStep
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
        .sheet(isPresented: $citySearch) { CitySearchView().presentationDetents([.medium, .large]) }
        // Інше місто — інші райони: обрані в попередньому не переносимо.
        .onChange(of: model.state?.city.name) { _, _ in places = [] }
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

    /// Артисти ще вантажаться (nil) чи є: секція стоїть. Порожньо чи збій — секції нема.
    private var hasArtists: Bool { model.state?.popularArtists?.isEmpty != true }

    /// Райони міста, а не місцевості: адміністративних кілька, і їх знають на ім'я.
    private var districts: [District] {
        (model.state?.city.districts ?? []).filter { !$0.isLocality }.sorted { $0.name < $1.name }
    }

    /// «Про що сказати?» — одне прохання стежити замість двох поспіль (критика 1.4): артисти, що гастролюють (поле й
    /// чипи, як у шторці радару), і райони міста. Секції без даних нема. Уже обрані з профілю позначені й не знімаються.
    private var followStep: some View {
        let followed = model.root.followedDistricts
        return question(Copy.onboarding_follow_title, Copy.onboarding_follow_hint) {
            // Надрядок секції одразу під поясненням читався його продовженням: відступ, як між секціями.
            VStack(alignment: .leading, spacing: Space.section) {
                if hasArtists {
                    VStack(alignment: .leading, spacing: Space.md) {
                        GroupLabel(title: Copy.onboarding_follow_artists)
                        PopularArtistChips(picked: $artists, dates: false, limit: onboardingArtists)
                    }
                }
                if !districts.isEmpty {
                    VStack(alignment: .leading, spacing: Space.md) {
                        // Місто ще може бути типовим (геолокацію питаємо після туру): чип каже, чиї це райони, і міняє місто.
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: Space.sm) { GroupLabel(title: Copy.onboarding_follow_places); cityChip }
                            VStack(alignment: .leading, spacing: Space.sm) { GroupLabel(title: Copy.onboarding_follow_places); cityChip }
                        }
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
            .padding(.top, Space.sm)
        }
    }

    private var cityChip: some View {
        Chip(
            label: model.state?.city.name ?? "", glyph: PoruchIcons.pin, trailingGlyph: PoruchIcons.chevronDown, selected: false
        ) { citySearch = true }
        .fixedSize()
    }

    /// Кроки, які є: без артистів (збій, порожньо) і без районів міста кроку «Про що сказати?» нема.
    private var steps: [OnboardingStep] {
        OnboardingStep.allCases.filter { $0 != .follow || hasArtists || !districts.isEmpty }
    }

    private var actionLabel: String {
        let picked = artists.count + places.count
        if step == .follow && picked > 0 { return Copy.radar_picker_follow("\(picked)") }
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
        if steps.contains(.follow) && hasArtists {
            model.app.followArtists(picked: Array(artists.values), from: "onboarding")
            let shown = min(model.state?.popularArtists?.count ?? 0, onboardingArtists)
            model.app.radarPickerClosed(shown: Int32(shown), picked: Int32(artists.count), from: "onboarding")
        }
        // Перемикач: уже обрані з профілю лишаються, бо в `places` їх не буває.
        for district in districts where places.contains(district.id) {
            model.app.toggleDistrictZone(district: district, from: "onboarding")
        }
        model.app.saveTaste(interests: interests, times: times, crowd: crowd)
    }
}

/// Кроки онбордингу: те, що читає ранжування, і одне «стежити» (артисти й райони) — привід повернутись. Кожен зайвий
/// екран — привід піти.
private enum OnboardingStep: Int, CaseIterable {
    case welcome, interests, times, crowd, follow
}

/// Скільки популярних артистів показати в онбордингу: під ними ще райони, решту знаходить поле.
private let onboardingArtists = 12

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
