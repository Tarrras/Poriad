import Foundation
import Shared

/// Стан деталей складає спільний `DetailPresenter` — та сама згортка, що й на Android: сеанс каруселі,
/// «якір» прокату, «Ще в цьому місці», дія нижньої панелі. Тут лише спостережувана обгортка на екран:
/// один `@Published`, тож деталі перемальовуються зі своїм станом, а не з кожною емісією `AppModel`.
final class DetailScreenModel: ObservableObject {
    @Published private(set) var state = DetailScreenState.companion.Empty
    private let presenter: DetailPresenter
    private var subscription: Subscription?

    init(app: PoruchApp, eventID: String) {
        presenter = DetailPresenter(app: app, openedId: eventID)
        subscription = presenter.observe { [weak self] state in self?.state = state }
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
        case .leave: Copy.going
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
        if room.awaitingApproval { return Copy.request_pending_hint }
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
