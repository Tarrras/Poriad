import SwiftUI

/// Підказки першого знайомства (docs/coach-marks.md): прожектор на справжньому елементі екрана й картка
/// з одним реченням про нього. Ніяких закликів — лише що це і що станеться після тапу.
enum CoachTip: String {
    case city, map, create, companion, invite, sheet

    var title: String {
        switch self {
        case .city: Copy.tip_city_title
        case .map: Copy.tip_map_title
        case .create: Copy.tip_create_title
        case .companion: Copy.tip_companion_title
        case .invite: Copy.tip_invite_title
        case .sheet: Copy.tip_sheet_title
        }
    }

    var body: String {
        switch self {
        case .city: Copy.tip_city_body
        case .map: Copy.tip_map_body
        case .create: Copy.tip_create_body
        case .companion: Copy.tip_companion_body
        case .invite: Copy.tip_invite_body
        case .sheet: Copy.tip_sheet_body
        }
    }

    /// Кожна підказка — раз на пристрій.
    var seen: Bool {
        get { UserDefaults.standard.bool(forKey: "poruch.tip.\(rawValue)") }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: "poruch.tip.\(rawValue)") }
    }
}

/// Де зараз елементи з підказками, у координатах вікна. Пише `coachTarget`, читає лише відкритий прожектор:
/// прокрутка головної не перемальовує нічого, поки підказки не видно. Власник — щоб зникнення старих деталей
/// не стерло рамку нових, що вже зʼявились на тому самому місці.
@MainActor @Observable final class CoachFrames {
    static let shared = CoachFrames()
    private var frames: [CoachTip: (owner: UUID, rect: CGRect, corner: CGFloat?)] = [:]

    func rect(_ tip: CoachTip) -> CGRect? { frames[tip]?.rect }
    /// Радіус кута цілі; `nil` — капсула (кнопка, пігулка, коло).
    func corner(_ tip: CoachTip) -> CGFloat? { frames[tip]?.corner }
    func place(_ tip: CoachTip, _ rect: CGRect, corner: CGFloat?, owner: UUID) { frames[tip] = (owner, rect, corner) }
    func remove(_ tip: CoachTip, owner: UUID) { if frames[tip]?.owner == owner { frames[tip] = nil } }

    /// Ціль цілком у вікні: підказка ніколи не вказує на те, що прокрутили чи сховали.
    func visible(_ tip: CoachTip) -> Bool {
        guard let rect = rect(tip), rect.width > 0,
              let window = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first
        else { return false }
        return window.bounds.contains(rect)
    }
}

extension View {
    /// Елемент, на який може вказати підказка `tip`. `nil` — нічого не робить (пункт таббару без підказки).
    /// `cornerRadius` — для прямокутної цілі (картка, рядок); без нього виріз — капсула, як у кнопки.
    func coachTarget(_ tip: CoachTip?, cornerRadius: CGFloat? = nil) -> some View {
        modifier(CoachTarget(tip: tip, corner: cornerRadius))
    }

    /// Показує `tips` по черзі над цим екраном, поки `enabled`: за 1,2 с після появи, лише в активному
    /// застосунку (не під системним питанням), без уже бачених і тих, чиєї цілі не видно. Перерваний тур
    /// (екран сховали) продовжується з тієї ж підказки. `onFinish` — раз, коли тур пройдено, пропущено чи нема що
    /// показати: після нього можна ставити наступне питання.
    func coachMarks(_ tips: [CoachTip], enabled: Bool, onFinish: @escaping () -> Void = {}) -> some View {
        modifier(CoachMarks(tips: tips, enabled: enabled, onFinish: onFinish))
    }
}

private struct CoachTarget: ViewModifier {
    let tip: CoachTip?
    let corner: CGFloat?
    @State private var owner = UUID()
    func body(content: Content) -> some View {
        if let tip {
            content.background {
                GeometryReader { proxy in
                    let frame = proxy.frame(in: .global)
                    Color.clear
                        .onAppear { CoachFrames.shared.place(tip, frame, corner: corner, owner: owner) }
                        .onChange(of: frame) { _, new in CoachFrames.shared.place(tip, new, corner: corner, owner: owner) }
                        .onDisappear { CoachFrames.shared.remove(tip, owner: owner) }
                }
            }
        } else {
            content
        }
    }
}

private struct CoachMarks: ViewModifier {
    let tips: [CoachTip]
    let enabled: Bool
    let onFinish: () -> Void
    @Environment(\.scenePhase) private var phase
    @Environment(\.appModel) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tour: [CoachTip] = []
    @State private var step = 0
    @State private var finished = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if enabled, step < tour.count {
                    CoachOverlay(tour: tour, step: step, next: next, skip: skip).transition(.opacity)
                }
            }
            // Нова фаза чи вимкнення скасовують відлік: системне питання про геолокацію не ділить екран з підказкою.
            .task(id: enabled && phase == .active) {
                guard enabled, phase == .active, tour.isEmpty, !finished else { return }
                try? await Task.sleep(for: .seconds(1.2))
                guard !Task.isCancelled else { return }
                let shown = tips.filter { !$0.seen && CoachFrames.shared.visible($0) }
                guard !shown.isEmpty else { return finish() }
                withAnimation(.easeOut(duration: 0.3)) { tour = shown }
            }
    }

    private var stepMotion: Animation { reduceMotion ? .easeInOut(duration: 0.25) : .spring(response: 0.5, dampingFraction: 0.82) }

    private func next() {
        // Другий тап по притемненню, що вже тане, приходить, коли тур скінчився.
        guard step < tour.count else { return }
        let tip = tour[step]
        tip.seen = true
        appModel?.app.tipAnswered(tip: tip.rawValue, action: step == tour.count - 1 ? "done" : "next")
        // Ціль наступної могла зникнути, поки читали цю: пропускаємо, а не вказуємо в порожнечу.
        var following = step + 1
        while following < tour.count, !CoachFrames.shared.visible(tour[following]) { following += 1 }
        withAnimation(stepMotion) { step = following }
        if following == tour.count { finish() }
    }

    private func skip() {
        guard step < tour.count else { return }
        tour[step...].forEach { $0.seen = true }
        appModel?.app.tipAnswered(tip: tour[step].rawValue, action: "skip")
        withAnimation(.easeOut(duration: 0.25)) { step = tour.count }
        finish()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinish()
    }
}

/// Притемнення з вирізом під ціль, кільце, що м'яко розходиться, і картка зі стрілкою до цілі.
private struct CoachOverlay: View {
    let tour: [CoachTip]
    let step: Int
    let next: () -> Void
    let skip: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    /// Перший кадр: виріз ширший за ціль і стягується на неї, картка виринає зі стрілки.
    @State private var focused = false

    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            if let target = CoachFrames.shared.rect(tour[step]) {
                let hole = target.offsetBy(dx: -origin.x, dy: -origin.y).insetBy(dx: -6, dy: -6)
                // Виріз на 6 pt ширший за ціль, тож і кут на 6 pt більший: краї лишаються паралельні.
                let corner = CoachFrames.shared.corner(tour[step]).map { $0 + 6 } ?? hole.height / 2
                let below = hole.midY < proxy.size.height / 2
                ZStack(alignment: .topLeading) {
                    Spotlight(
                        hole: focused || reduceMotion ? hole : hole.insetBy(dx: -56, dy: -56),
                        radius: focused || reduceMotion ? corner : corner + 56
                    )
                        .fill(Color.black.opacity(scheme == .dark ? 0.62 : 0.45), style: FillStyle(eoFill: true))
                        .contentShape(Rectangle())
                        .onTapGesture(perform: next)
                        .accessibilityHidden(true)
                    if !reduceMotion { ring(hole, corner: corner) }
                    bubble(hole: hole, size: proxy.size, below: below)
                }
            }
        }
        .ignoresSafeArea()
        .sensoryFeedback(.selection, trigger: step)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, skip)
        .onAppear { withAnimation(.spring(response: 0.55, dampingFraction: 0.8).delay(0.05)) { focused = true } }
    }

    /// Кільце довкола вирізу: розходиться й тане, як коло на воді. Показує, куди дивитись, без миготіння.
    private func ring(_ hole: CGRect, corner: CGFloat) -> some View {
        Color.clear
            .phaseAnimator([false, true]) { _, spread in
                RoundedRectangle(cornerRadius: corner + (spread ? 12 : 0), style: .continuous).stroke(Color.white, lineWidth: 2)
                    .padding(spread ? -12 : 0).opacity(spread ? 0 : 0.7)
            } animation: { spread in spread ? .easeOut(duration: 1.5) : nil }
            .frame(width: hole.width, height: hole.height)
            .position(x: hole.midX, y: hole.midY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func bubble(hole: CGRect, size: CGSize, below: Bool) -> some View {
        let width = min(340, size.width - 2 * Space.page)
        // Запасу менше за поле — картка стоїть по центру, а не з'їжджає на 3 pt від кроку до кроку.
        let free = size.width - 2 * Space.page - width
        let x = free < Space.page ? (size.width - width) / 2 : min(max(hole.midX - width / 2, Space.page), size.width - Space.page - width)
        // Стрілка навпроти центру цілі, але на прямому краї, а не на заокругленні кута картки.
        let inset = Corner.md + 13
        let arrowX = min(max(hole.midX - x, inset), width - inset)
        let gap: CGFloat = 10
        return CoachBubble(tip: tour[step], index: step, count: tour.count, arrowX: arrowX, below: below, next: next, skip: skip)
            .frame(width: width)
            .id(step)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.94, anchor: UnitPoint(x: arrowX / width, y: below ? 0 : 1))),
                removal: .opacity
            ))
            .scaleEffect(focused || reduceMotion ? 1 : 0.9, anchor: UnitPoint(x: arrowX / width, y: below ? 0 : 1))
            .opacity(focused || reduceMotion ? 1 : 0)
            .padding(.leading, x)
            .padding(.top, below ? hole.maxY + gap : 0)
            .padding(.bottom, below ? 0 : size.height - hole.minY + gap)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: below ? .topLeading : .bottomLeading)
    }
}

/// Картка підказки: назва кондензом, одне речення, крапки кроків, «Пропустити» і «Далі». Одна підказка — лише «Зрозуміло».
private struct CoachBubble: View {
    let tip: CoachTip
    let index: Int
    let count: Int
    let arrowX: CGFloat
    let below: Bool
    let next: () -> Void
    let skip: () -> Void

    private var last: Bool { index == count - 1 }

    var body: some View {
        // −1: вістря заходить під картку, без волосяної щілини між ними.
        VStack(spacing: -1) {
            if below { arrow(up: true) }
            card
            if !below { arrow(up: false) }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(tip.title).font(PoruchFont.brandTitle3).kerning(-0.1).foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(tip.body).font(PoruchFont.subhead).foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Space.md) {
                if count > 1 { dots }
                Spacer(minLength: 0)
                if !last {
                    Button(Copy.onboarding_skip, action: skip)
                        .font(PoruchFont.label).foregroundStyle(Palette.inkSecondary).frame(minHeight: 44)
                }
                Button(action: next) {
                    Text(last ? Copy.tip_done : Copy.next).font(PoruchFont.button).foregroundStyle(Palette.onBrand)
                        .padding(.horizontal, Space.xl).frame(minHeight: 40)
                        // Кут квитка, як у кожної кнопки застосунку: пігулки — лише чипи, бейджі, пошук і таббар.
                        .background(Palette.brand, in: RoundedRectangle(cornerRadius: Corner.md, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: Corner.md, style: .continuous))
                }
                .buttonStyle(PressableStyle(pressedScale: 0.95))
            }
        }
        .padding(Space.lg)
        .background(Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: Corner.md, style: .continuous))
        .lifted(Elevation.overlay)
    }

    /// Пройдене й поточне — довшою рискою, як прогрес онбордингу.
    private var dots: some View {
        HStack(spacing: Space.xs) {
            ForEach(0..<count, id: \.self) { position in
                // Решта — притишеним третім чорнилом: тонова плашка на піднятій картці вночі зливалась.
                Capsule().fill(position == index ? Palette.brand : Palette.inkTertiary.opacity(0.5))
                    .frame(width: position == index ? 16 : 6, height: 6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Copy.tip_step("\(index + 1)", "\(count)"))
    }

    private func arrow(up: Bool) -> some View {
        Arrow().fill(Palette.surfaceRaised)
            .frame(width: 18, height: 9)
            .rotationEffect(.degrees(up ? 180 : 0))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, arrowX - 9)
            .accessibilityHidden(true)
    }
}

/// Усе полотно мінус виріз під ціллю. Рамка й кут анімуються: прожектор переїжджає від цілі до цілі й міняє форму.
private struct Spotlight: Shape {
    var hole: CGRect
    var radius: CGFloat
    var animatableData: AnimatablePair<CGRect.AnimatableData, CGFloat> {
        get { AnimatablePair(hole.animatableData, radius) }
        set { hole.animatableData = newValue.first; radius = newValue.second }
    }
    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addRoundedRect(in: hole, cornerSize: CGSize(width: radius, height: radius), style: .continuous)
        return path
    }
}

/// Вістря вниз; угору — поворотом.
private struct Arrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.maxY * 2))
        path.closeSubpath()
        return path
    }
}
