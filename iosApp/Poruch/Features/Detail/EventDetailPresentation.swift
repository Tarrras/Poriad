import Foundation
import SwiftUI
import Shared

/// Стан деталей складає спільний `DetailPresenter` — та сама згортка, що й на Android: сеанс каруселі,
/// «якір» прокату, «Ще в цьому місці», дія нижньої панелі. Тут лише спостережувана обгортка на екран:
/// один `@Published`, тож деталі перемальовуються зі своїм станом, а не з кожною емісією `AppModel`.
final class DetailScreenModel: ObservableObject {
    @Published private(set) var state = DetailScreenState.companion.Empty
    /// `event_details` доїхали без збою: у події справжні `media`. Доти слот тримає картку з `media = []`, і правка з неї
    /// стерла б фото й відео організатора (рев'ю M1-ios). `DetailScreenState` збою не несе, тож дивимось у сам стан —
    /// він не старший за емісію презентера.
    @Published private(set) var detailsLoaded = false
    private let presenter: DetailPresenter
    private let app: PoruchApp
    private var subscription: Subscription?

    init(app: PoruchApp, eventID: String) {
        self.app = app
        presenter = DetailPresenter(app: app, openedId: eventID)
        // Перший кадр — уже з подією: zoom з квитка не розгортається в порожнє полотно, поки колбек дійде.
        state = presenter.state.value as? DetailScreenState ?? state
        subscription = presenter.observe { [weak self] state in self?.apply(state) }
    }

    private func apply(_ state: DetailScreenState) {
        let detail = (app.state.value as? AppState)?.detail
        let loaded = !state.loading && state.event != nil && detail?.failure == nil && detail?.event?.id == state.event?.id
        if detailsLoaded != loaded { detailsLoaded = loaded }
        self.state = state
    }

    /// Сеанс на екрані: усі дії (участь, збереження, скарга, мапа) ідуть на нього, не на картку, з якою відкрили.
    var sessionID: String { presenter.sessionId }
    /// Інша дата в каруселі прокату.
    func pickSession(_ id: String) { presenter.pickSession(id: id) }
    /// Екран знову зверху після іншого екрана деталей: той перебрав єдиний слот відкритої події.
    func reopen() { presenter.reopen() }
    /// Id картки для мапи: для другої дати прокату — представник.
    func cardID() -> String { presenter.cardId() }
    func refresh() async { try? await presenter.refresh() }

    /// «На мапі»: слот відкритої події переходить мапі як фокус, і при знятті екрана ми його не чистимо.
    var handedOff = false

    // Зняття екрана — це звільнення `@StateObject`, а не `onDisappear`: той спрацьовує й коли зверху пушать інший екран.
    deinit {
        subscription?.close()
        presenter.release(keepSlot: handedOff)
    }
}

extension DetailAction {
    var title: String {
        switch self {
        case .join: Copy.join
        case .request: Copy.request_join
        case .requested: Copy.request_pending
        // «Ви йдете» каже штамп поруч; кнопка — що станеться від дотику.
        case .leave: Copy.leave
        case .joinWaitlist: Copy.join_waitlist
        case .leaveWaitlist: Copy.leave_waitlist
        case .organizer: Copy.you_organize
        case .tickets: Copy.listing_tickets
        default: Copy.cancelled_short
        }
    }
}

extension DetailScreenState {
    /// Чат учасників поза застосунком: лише https, інакше кнопки нема.
    var contactURL: URL? { contactUrl.flatMap { URL(string: $0) } }

    /// Рядок під датою в нижній панелі: місця й черга для кімнати, ціна або причина відсутності кнопки для афіші.
    var seatsSummary: String {
        guard event != nil else { return "" }
        if cancelled { return Copy.cancelled }
        if let listing {
            if listing.state == .postponed { return Copy.state_postponed_summary }
            if listing.isWithdrawn { return Copy.state_unknown }
            if sessionStarted { return Copy.session_started_hint }
            return listing.hasSource ? listingPrice(listing) : Copy.listing_hint_no_link
        }
        guard let room else { return "" }
        if ended { return Copy.event_ended }
        if room.awaitingApproval { return room.payOnline ? Copy.pay_waiting_hint : Copy.request_pending_hint }
        // Гостю — що його чекає, не текст перемикача з редактора.
        if room.approvalRequired && !room.joined && !organizer { return Copy.approval_guest_hint }
        if room.isFull && !room.joined && !organizer { return Copy.waitlist_hint }
        return Copy.seats("\(room.seatsLeft)")
    }
}

extension Listing {
    /// Пояснення стану афіші над продавцями (R8). Null — «в силі» без переносу.
    func stateHint(_ event: Event) -> String? {
        if event.isCancelled { return Copy.state_cancelled_hint }
        switch state {
        case .postponed: return Copy.state_postponed_hint
        case .unknown: return Copy.state_unknown_hint
        default: return isMoved ? Copy.state_moved_hint(previousDate(event) ?? "") : nil
        }
    }
}

/// «Перевірено сьогодні о 09:00» — довіра до «в силі» (R8).
func checkedText(_ checked: CheckedLabel) -> String {
    switch checked.day {
    case .today: return Copy.checked_today(checked.time)
    case .yesterday: return Copy.checked_yesterday(checked.time)
    default: return Copy.checked_date(checked.date)
    }
}

/// Для кого подія, на картці, а не через відмову сервера.
func ageLimitLabel(_ room: Gathering) -> String? {
    guard room.hasAgeLimit else { return nil }
    if let maximum = room.maxAge { return Copy.age_badge_range("\(room.minAge)", "\(maximum.intValue)") }
    return "\(room.minAge)+"
}

/// Причини скарги в порядку шторки.
let reportReasons: [(value: ReportReason, title: String)] = [
    (.minors, Copy.reason_minors),
    (.safety, Copy.reason_safety),
    (.harassment, Copy.reason_harassment),
    (.scam, Copy.reason_scam),
    (.spam, Copy.reason_spam),
    (.other, Copy.category_other)
]

// ---- Оплата онлайн: умови перед заявкою

/// Умови перед заявкою на онлайн-подію: гроші напряму організатору, «Поряд» не приймає оплату, правила повернення.
/// Згода зберігається на сервері (`accept_pay_terms`) разом із заявкою.
struct PayTermsSheet: View {
    let event: Event
    let agree: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                Text(Copy.pay_terms_title).font(PoruchFont.brandTitle2).foregroundStyle(Palette.ink)
                Text(Copy.pay_terms_body).font(PoruchFont.bodyText).foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: Space.sm) {
                    ForEach([Copy.pay_terms_direct, refundText(event.gathering?.refundPolicy), Copy.pay_terms_doubt].compactMap { $0 }, id: \.self) { line in
                        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                            Text("•").foregroundStyle(Palette.inkTertiary)
                            Text(line).font(PoruchFont.subhead).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                PrimaryButton(title: Copy.pay_terms_agree) { agree() }
                SecondaryButton(title: Copy.cancel) { dismiss() }
            }
            .padding(Space.page)
        }
    }
}

/// Правила повернення людськими словами; онлайн-подія без правил (стара) — nil.
func refundText(_ policy: RefundPolicy?) -> String? {
    guard let policy else { return nil }
    let rule = switch policy {
    case .before48h: Copy.refund_before_48h
    case .before24h: Copy.refund_before_24h
    default: Copy.refund_cancel_only
    }
    return "\(rule) \(Copy.refund_organizer_cancels)"
}

/// Онлайн-подія: умови оплати перед заявкою; після згоди — заявка й розмова з організатором. Розмова відкривається,
/// коли заявка справді пройшла (після дати народження теж) і шторка вже закрилась: два переходи разом SwiftUI губить.
/// Подія, для якої показуємо умови (Event з Kotlin не Identifiable).
struct PayTermsTarget: Identifiable {
    let event: Event
    var id: String { event.id }
}

struct PayTermsFlow: ViewModifier {
    @EnvironmentObject var model: AppModel
    @Binding var target: PayTermsTarget?
    @Binding var writingTo: ChatRoute?
    @Binding var joinTapped: Bool
    /// `DetailScreenState.opensPaymentChat`: заявка на онлайн-подію вже є.
    let requested: Bool
    @State private var agreed: Event?
    @State private var sheetOpen = false
    /// `requested` у стані: замикання onDismiss тримає значення з миті, коли шторку показали.
    @State private var isRequested = false

    func body(content: Content) -> some View {
        content.sheet(item: $target, onDismiss: { sheetOpen = false; openChat() }) { target in
            PayTermsSheet(event: target.event) {
                joinTapped = true
                model.app.requestOnlineEvent(id: target.event.id)
                agreed = target.event
                self.target = nil
            }
            .presentationDetents([.medium, .large])
            .onAppear { sheetOpen = true }
        }
        .onChange(of: requested, initial: true) { _, now in isRequested = now; openChat() }
    }

    private func openChat() {
        guard let done = agreed, isRequested, !sheetOpen, let me = model.state?.session.userId else { return }
        agreed = nil
        writingTo = ChatRoute(id: done.id, thread: me)
    }
}
