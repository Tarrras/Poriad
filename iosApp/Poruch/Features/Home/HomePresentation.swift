import Foundation
import Shared

/// Списки головної, зібрані раз зі спільного стану, а не в тілі view на кожне перемальовування.
struct HomePresentation {
    let signedIn: Bool
    let cityName: String
    /// Стрічка головної ще їде.
    let loading: Bool
    /// Пошук головної ще їде.
    let searchLoading: Bool
    /// Нове від закладів і організаторів, за якими стежу, найближчі першими.
    let followed: [Event]
    /// «Ваше»: до `HomeRules.PERSONAL_LIMIT` своїх подій, спершу ті, де хтось чекає відповіді.
    let personal: [PersonalRow]
    /// Скільки подій, що чекають відповіді (чат, запит), у «Ваше» не влізло: рядок «Чекають відповіді: ще N».
    let moreWaiting: Int
    /// «Від людей»: зустрічі з вільним місцем окремою рейкою, коли їх набралось досить (`HomeRules.people`); інакше порожньо.
    let people: [FeedEntry]
    /// «У місті»: одна стрічка з «Для вас», афіші міста й підписок.
    let feed: [FeedEntry]
    /// Чипи над сіткою (без великих карток): що з цієї стрічки можна відфільтрувати. Порожньо — рядка нема.
    let chips: [FeedFilter]
    /// Скільки подій в області, без фільтрів мапи.
    let totalFound: Int
    /// Скільки відкритих зустрічей від людей у місті всього: число в «Усі N» біля «Від людей», рейка показує лише перші.
    let openRooms: Int
    /// Пошук головної, окремий від мапи: фільтр одного екрана не порожнить інший.
    let searchText: String
    /// Результати пошуку одним списком, без дайджесту. Лише ті, чиї картки вже приїхали.
    let results: [Event]
    /// Id усього знайденого, у порядку видачі: з нього довантажують картки наступного шматка.
    let resultIDs: [String]
    /// Скільки знайдено насправді.
    let resultsTotal: Int
    /// Заклади за тим самим запитом: секція «Місця» під подіями.
    let places: [Place]
    let artists: [ArtistHit]
    /// Фільтри пошуку: усі міста чи лише обране, категорія, дата. Стрічку не звужують.
    let searchEverywhere: Bool
    let searchCategory: EventCategory?
    let searchDate: DateFilter

    var searching: Bool { !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Місто з подіями, назване в пошуку, крім поточного. Пошук усюди його вже охоплює.
    var cityMatch: HomeLocation? {
        searching && !searchEverywhere ? HomeLocation.companion.mentioned(query: searchText, current: cityName) : nil
    }

    /// Де шукає поле: без цього неочевидно, що пошук іде лише в обраному місті.
    var searchScope: String { searchEverywhere ? "усюди" : "у місті \(cityName)" }

    /// Будь-яка зміна запиту чи фільтрів — нова видача: «Показати ще» починає спочатку.
    var searchKey: String { "\(searchText)|\(searchEverywhere)|\(searchCategory?.key ?? "*")|\(searchDate.name)" }

    /// Перші `limit` знайдених, чиї картки вже приїхали. `found` пропускає ті, що ще їдуть,
    /// тож беремо за id, а не `prefix`: інакше пізніша картка стала б на місце неприїхалої.
    func results(limit: Int) -> [Event] {
        let wanted = Set(resultIDs.prefix(limit))
        return results.filter { wanted.contains($0.id) }
    }

    private let savedIds: Set<String>
    private let waitlistedIds: Set<String>

    init(state: AppState?) {
        signedIn = state?.signedIn == true
        cityName = state?.city.name ?? HomeLocation.companion.Kyiv.city
        // Своя стрічка: та сама область, що на мапі, але без її фільтрів.
        let home = state?.home
        loading = home?.loading == true
        searchLoading = home?.searchLoading == true
        totalFound = Int(home?.totalFound ?? 0)
        openRooms = Int(home?.openRooms ?? 0)
        resultsTotal = Int(home?.resultsTotal ?? 0)
        places = home?.places ?? []
        artists = home?.artists ?? []
        searchText = home?.searchText ?? ""
        searchEverywhere = home?.searchEverywhere == true
        searchCategory = home?.searchCategory
        searchDate = home?.searchDate ?? .any
        savedIds = Set(state?.library.savedIds ?? [])
        waitlistedIds = Set(state?.library.waitlistedIds ?? [])
        // І свої, і ті, куди йду: `concerns` — те саме правило, що в нагадуваннях. Лише те, що ще не завершилось, як на Android.
        let mine = state?.library.myEvents ?? []
        let now = nowInstant()
        let plans = mine.filter { state?.concerns(event: $0) == true && $0.isPublished && $0.isCurrent(now: now) }.sorted { $0.startsAt < $1.startsAt }
        // Порядок дає сервер; за час, що картка лежить у стані, подія могла скінчитись чи зникнути.
        followed = (state?.library.followEvents ?? []).filter { $0.isPublished && $0.isCurrent(now: now) }

        // Увесь екран в одному порядку. Картки до індексу прив'язує спільний код: тут лише
        // завантажені, десятки, а не тисячі записів індексу через міст.
        let ranked = home?.events ?? []
        let suggested = Array((home?.suggested ?? []).prefix(homeSuggestedLimit))
        // Те, що вже в «Для вас», у списку міста не повторюємо.
        let shown = Set(suggested.map(\.id))
        let remaining = ranked.filter { !shown.contains($0.id) }
        // Місто: куди можна піти сьогодні, включно з прокатами, далі решта за рангом. Але те, що сьогодні
        // починається, йде першим: прокат буде відкритий і завтра. `Calendar.current` — новий
        // об'єкт на кожне звертання, тому один на цикл.
        let calendar = Calendar.current
        var startingToday: [Event] = []
        var later: [Event] = []
        for event in remaining {
            if let date = parseEventDate(event.startsAt), calendar.isDateInToday(date) {
                startingToday.append(event)
            } else {
                later.append(event)
            }
        }
        let runningToday = later.filter { $0.isUnderway(now: now) }
        let runningIds = Set(runningToday.map(\.id))
        let city = startingToday + runningToday + later.filter { !runningIds.contains($0.id) }
        results = home?.found ?? []
        resultIDs = (home?.results ?? []).map(\.id)

        // «Ваше»: чат із непрочитаним (навіть минулої події) і запити чекають на людину, тож вони першими.
        let mineById = Dictionary(mine.map { ($0.id, $0) }) { first, _ in first }
        let unread = state?.chatUnread ?? []
        let chats = Dictionary(unread.map { ($0.eventId, $0) }) { first, _ in first }
        let pending = state?.library.pendingRequests ?? []
        let asks = RequestRules.shared.pendingByEvent(requests: pending)
        let waiting = unread.compactMap { mineById[$0.eventId] } + pending.compactMap { mineById[$0.eventId] }.filter { $0.isCurrent(now: now) }
        var seen = Set<String>()
        let mineFirst = (waiting + plans).filter { seen.insert($0.id).inserted }
        personal = mineFirst.prefix(Int(HomeRules.shared.PERSONAL_LIMIT))
            .map { PersonalRow(event: $0, chat: chats[$0.id], requests: asks[$0.id]?.intValue ?? 0, organizing: state?.organizes(event: $0) == true) }
        moreWaiting = Set(waiting.map(\.id)).subtracting(personal.map(\.event.id)).count
        // Усі свої плани, а не лише три з «Ваше»: решта живе в «Моїх подіях», а в місті стояла б безіменним постером.
        let mineIds = Set(mineFirst.map(\.id))
        people = HomeRules.shared.people(forYou: suggested, city: city, following: followed, skip: mineIds)
        // Кімнати, що дістали власну секцію, у стрічці не повторюємо й уперед їх більше не ставимо.
        feed = HomeRules.shared.feed(
            forYou: suggested, city: city, following: followed, skip: mineIds.union(people.map(\.event.id)), roomsFirst: people.isEmpty
        )
        chips = HomeRules.shared.chips(entries: Array(feed.dropFirst(homeHeroCount)), now: now, zoneId: TimeZone.current.identifier)
    }

    /// У «Ваше», «Від людей» і «У місті» нема нічого: тоді стрічка каже про це словами.
    var isEmpty: Bool { personal.isEmpty && people.isEmpty && feed.isEmpty }

    func isSaved(_ event: Event) -> Bool { savedIds.contains(event.id) }
    func isWaitlisted(_ event: Event) -> Bool { waitlistedIds.contains(event.id) }
}

/// Рядок блоку «Ваше»: своя подія, її непрочитаний чат і скільки людей просяться.
struct PersonalRow: Identifiable {
    let event: Event
    let chat: ChatUnread?
    let requests: Int
    /// Організую, а не йду.
    let organizing: Bool
    var id: String { event.id }
}

/// Кількість великих карток над сіткою «У місті»: одне число з домену, бо стрічка кладе в них зустрічі від людей.
let homeHeroCount = Int(HomeRules.shared.HERO_COUNT)
/// Більше за це «для вас» перестає бути добіркою.
let homeSuggestedLimit = 4
/// Скільки результатів пошуку показує головна.
let homeResultsLimit = 12
