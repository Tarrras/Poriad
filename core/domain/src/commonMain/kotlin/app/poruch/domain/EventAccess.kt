package app.poruch.domain

/**
 * Доступ до подій, розбитий на п'ять інтерфейсів за правами на сервері: читати може будь-хто,
 * зберігати — власник списку, створювати й скасовувати — організатор, приєднуватись — гість,
 * відповідати на запити — знову організатор. Так екран бачить лише те, що йому справді треба,
 * а тестова підробка реалізує два методи, а не двадцять.
 */
data class EventQuery(
    val south: Double, val west: Double, val north: Double, val east: Double,
    val category: String? = null, val from: String? = null, val to: String? = null,
    val text: String? = null, val available: Boolean = false
)

/** Читання. Єдина грань, яка щось віддає гостю без акаунта. */
interface EventDiscovery {
    /** Усе в області: повний тонкий індекс для мапи й ранжування плюс перше вікно карток. */
    suspend fun discover(query: EventQuery): DiscoveryPage

    /** Остання відповідь з кешу пристрою, щоб мапі було що малювати до відповіді мережі. */
    fun cached(query: EventQuery): DiscoveryPage

    /** Картки за id, до [DiscoveryRules.CARD_BATCH] за раз: вікно стрічки, стос майданчика, добірка головної. */
    suspend fun cards(ids: List<String>): List<Event>

    suspend fun details(id: String): Event?

    /** Свої: організовані, відвідувані та збережені. */
    suspend fun myEvents(): List<Event>

    /** Учасники події. Бачать лише організатор і учасники, решта отримує порожній список. */
    suspend fun attendees(id: String): List<Attendee>

    /** Скидає кеш попереднього акаунта. Викликати при зміні користувача. */
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

    /** Події, де цей акаунт у черзі. */
    suspend fun waitlistIds(): List<String>
    suspend fun joinWaitlist(id: String)
    suspend fun leaveWaitlist(id: String)

    /** Оцінки завершеної події: організаторові всі, учасникові — своя. */
    suspend fun ratings(id: String): List<EventRating>
    suspend fun rate(id: String, score: Int, comment: String?)
}

/** Двері організатора: хто просить увійти і кого впустити. */
interface EventRequests {
    /** Хто проситься на мою подію. Порожньо для всіх, крім організатора. */
    suspend fun joinRequests(id: String): List<Attendee>

    /** Усі запити до всіх моїх подій, що ще тривають: для головної і сповіщень. Свіжіші першими. */
    suspend fun pendingRequests(): List<JoinRequest>
    suspend fun approveMember(eventId: String, userId: String)
    suspend fun declineMember(eventId: String, userId: String)
}
