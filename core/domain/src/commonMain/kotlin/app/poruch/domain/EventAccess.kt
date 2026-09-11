package app.poruch.domain

/**
 * Що саме застосунок робить з подіями — п'ятьма гранями замість однієї.
 *
 * Досі це був один інтерфейс на двадцять один метод, і кожен, кому треба було прочитати деталі
 * події, отримував разом із ними право її скасувати, завантажити фото й схвалити чужий запит.
 * Це не теорія: `EventActions` бере доступ до подій, щоб викликати п'ять методів, а бачив усі; у
 * тестах підробка мусила реалізувати двадцять один, щоб перевірити два.
 *
 * Межі проведені за тим, чого вимагає сервер, а не за зручністю. Читати може будь-хто; зберігати —
 * лише власник свого списку; створювати й скасовувати — організатор; приєднуватись — гість;
 * відповідати на запити — знову організатор, але вже іншими правами. Кожна з цих п'яти груп в
 * Postgres захищена окремо, і клієнт тепер відбиває той самий поділ.
 */
data class EventQuery(
    val south: Double, val west: Double, val north: Double, val east: Double,
    val category: String? = null, val from: String? = null, val to: String? = null,
    val text: String? = null, val available: Boolean = false
)

/** Читання. Єдина грань, яка щось віддає гостю без акаунта. */
interface EventDiscovery {
    /**
     * Усе, що є в цій області, — і перше вікно карток разом із цим.
     *
     * Повертає [DiscoveryPage], а не список подій, бо це два різні питання в одній відповіді:
     * повний тонкий індекс для мапи й ранжування, і стільки карток, скільки видно з першого
     * погляду. Доки відповідь була одна, вона важила 306 КБ і мусила мати стелю в 300 рядків.
     */
    suspend fun discover(query: EventQuery): DiscoveryPage

    /** Остання відповідь із пам'яті пристрою: мапі є що малювати ще до відповіді мережі. */
    fun cached(query: EventQuery): DiscoveryPage

    /**
     * Картки для названих подій. Вікно стрічки, стос майданчика, добірка головної — усе це
     * однакове питання, і сервер відповідає на нього однією подорожжю замість [CARD_BATCH].
     */
    suspend fun cards(ids: List<String>): List<Event>

    suspend fun details(id: String): Event?

    /** Свої: організовані, відвідувані та збережені — усе, що належить цьому акаунту. */
    suspend fun myEvents(): List<Event>

    /** Roster of an event. Identities are visible to its organizer and members only; others get none. */
    suspend fun attendees(id: String): List<Attendee>

    /** Викидає з пам'яті все, що належало попередньому акаунту. Викликається при зміні особи. */
    fun clearPrivateCache()
}

/** Закладки. Приватний список, якого не бачить ніхто, крім власника. */
interface SavedEvents {
    suspend fun savedIds(): List<String>
    suspend fun save(id: String)
    suspend fun unsave(id: String)
}

/** Свої події: створити, змінити, скасувати. Сервер віддає це лише організаторові. */
interface EventAuthoring {
    suspend fun create(id: String, draft: EventDraft): String
    suspend fun update(id: String, draft: EventDraft): String
    suspend fun cancel(id: String)
    suspend fun uploadImage(eventId: String, bytes: ByteArray, contentType: String): String
}

/** Участь: двері й черга під ними. */
interface EventParticipation {
    suspend fun join(id: String)
    suspend fun leave(id: String)

    /** Events this account is queued for. Positions are private to their holder. */
    suspend fun waitlistIds(): List<String>
    suspend fun joinWaitlist(id: String)
    suspend fun leaveWaitlist(id: String)
}

/** Двері організатора: хто просить увійти і кого впустити. */
interface EventRequests {
    /** People asking to come to an event of mine. Empty for anyone but its organizer. */
    suspend fun joinRequests(id: String): List<Attendee>
    suspend fun approveMember(eventId: String, userId: String)
    suspend fun declineMember(eventId: String, userId: String)
}
