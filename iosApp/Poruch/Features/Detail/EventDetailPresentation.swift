import Foundation
import Shared

/// Єдина дія нижньої панелі. Рахується в одному місці, щоб підпис, тап і доступність не розходились.
enum DetailAction {
    case join, request, requested, leave, joinWaitlist, leaveWaitlist, organizer, cancelled
    /// Афіша: сторінка джерела.
    case tickets
    /// Кнопки нема: афіша без посилання, знята подія або зіпсований рядок.
    case none

    var title: String {
        switch self {
        case .join: Copy.join
        case .request: Copy.request_join
        case .requested: Copy.request_pending
        case .leave: Copy.going
        case .joinWaitlist: Copy.join_waitlist
        case .leaveWaitlist: "Ви в черзі"
        case .organizer: Copy.you_organize
        case .tickets: Copy.listing_tickets
        case .cancelled, .none: "Скасовано"
        }
    }

    var isEnabled: Bool {
        switch self {
        case .join, .request, .leave, .joinWaitlist, .leaveWaitlist, .tickets: true
        default: false
        }
    }
}

/// Проєкція спільного стану для однієї події: рахується раз на рендер і єдина вирішує, що екран пропонує.
struct EventDetailPresentation {
    let event: Event?
    let attendees: [Attendee]
    let mutating: Bool
    let signedIn: Bool
    let saved: Bool
    let waitlisted: Bool
    let organizer: Bool
    /// Хто проситься. Непорожньо лише для організатора.
    let requests: [Attendee]
    /// Чат учасників. Сервер віддає його лише організатору й підтвердженим, тож є посилання — є кому показати.
    var contactURL: URL? {
        guard let raw = event?.gathering?.contactUrl, let url = URL(string: raw), url.scheme == "https" else { return nil }
        return url
    }
    /// Сеанс прокату вже почався: показати можна, купити квиток — ні. Тижневої виставки не стосується.
    let sessionStarted: Bool
    /// Подія завершилась: участь уже нічого не змінює.
    let ended: Bool
    /// Учасник і вікно оцінки ще відкрите.
    let canRate: Bool
    /// Організаторові всі оцінки, учасникові — своя.
    let ratings: [EventRating]
    var myRating: EventRating? { ratings.first { $0.mine } }
    /// Хто шукає компанію на цю афішу: картки супутників без імен.
    let companions: [CompanionCard]
    /// Кнопка «Шукаю компанію»: афіша ще попереду, мого пошуку на неї нема.
    let canSeekCompany: Bool

    /// `sessions` — карусель дат: від неї залежить лише, чи ховати кнопку квитка на сеансі, що почався.
    init(state: AppState?, eventID: String, sessions: [EventSession] = []) {
        // Лише відкрита подія або інша дата її прокату: знімок стану в першу мить ще тримає попередню.
        let event = state?.detail.event.flatMap { selected in
            selected.id == eventID || sessions.contains(where: { $0.id == selected.id }) ? selected : nil
        }
        self.event = event
        attendees = state?.detail.attendees ?? []
        mutating = state?.mutating == true
        signedIn = state?.signedIn == true
        // Від обраної картки: після перемикання дати зберігається той вечір, що на екрані.
        saved = event.map { state?.isSaved(id: $0.id) == true } ?? false
        waitlisted = event.map { state?.isWaitlisted(id: $0.id) == true } ?? false
        organizer = event.flatMap { state?.organizes(event: $0) } ?? false
        requests = state?.detail.joinRequests ?? []
        sessionStarted = event.map { sessions.count > 1 && !$0.isMultiDay && $0.hasStarted(now: nowInstant()) } ?? false
        ended = event?.hasEnded(now: nowInstant()) == true
        canRate = event.map { RatingRules.shared.canRate(event: $0, now: nowInstant()) } ?? false
        ratings = state?.detail.ratings ?? []
        companions = event != nil ? state?.detail.companions ?? [] : []
        canSeekCompany = event != nil && state?.detail.canSeekCompany(now: nowInstant()) == true
    }

    var cancelled: Bool { event?.isCancelled == true }

    /// Кімната, якщо це кімната. Місця й участь лише в неї.
    var room: Gathering? { event?.gathering }

    /// Супутник «Йдемо разом»: час і місце тримає сервер, редагувати нема чого.
    var companionOf: CompanionParent? { room?.companionOf }

    /// Оголошення, якщо це афіша. Тоді дія одна: вийти на джерело.
    var listing: Listing? { event?.listing }

    var full: Bool { room?.isFull == true }

    /// Чат є для своїх: організатора й підтверджених. Скасована подія лишає його для читання.
    var hasChat: Bool { room != nil && (organizer || room?.joined == true) }

    /// Афіша відгалужується першою: кнопка «приєднатися», яка гарантовано отримає відмову, гірша за відсутність кнопки.
    var action: DetailAction {
        guard event != nil else { return .none }
        if cancelled { return .cancelled }
        if let listing { return listing.isWithdrawn || !listing.hasSource || sessionStarted ? .none : .tickets }
        if organizer { return .organizer }
        if ended { return .none }
        // Ні кімнати, ні оголошення — зіпсований рядок: без дій.
        guard let room else { return .none }
        if room.awaitingApproval { return .requested }
        if room.joined { return .leave }
        if waitlisted { return .leaveWaitlist }
        if room.approvalRequired { return .request }
        return room.isFull ? .joinWaitlist : .join
    }

    /// Рядок під датою в нижній панелі: місця й черга для кімнати, ціна або причина відсутності кнопки для афіші.
    var seatsSummary: String {
        guard event != nil else { return "" }
        if cancelled { return Copy.cancelled }
        if let listing {
            if listing.isWithdrawn { return Copy.listing_withdrawn_hint }
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
