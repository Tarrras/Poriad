package app.poruch.domain

/** Запит на участь у моїй події, як його віддає `my_join_requests`. [requestedAt] — ISO-8601. */
data class JoinRequest(
    val eventId: String,
    val userId: String,
    val name: String,
    val avatarUrl: String?,
    val requestedAt: String
) {
    /**
     * Ключ «уже показано»: той самий запит після повторного відкриття не має дзвонити двічі.
     * З часом запиту: відхилений і надісланий знову — це новий запит, і про нього треба сказати.
     */
    val key get() = "$eventId:$userId:$requestedAt"
}

/** Сповіщення про нові запити до однієї події. Одне на подію, а не на людину: три запити — один рядок. */
data class RequestAlert(val eventId: String, val eventTitle: String, val count: Int)

/**
 * Показує сповіщення негайно. Реалізує платформа. Пуш-інфраструктури нема, тож сповіщення
 * приходить, коли застосунок перечитав «мої події»: при відкритті й після кожної дії.
 */
interface RequestNotifier {
    fun notify(alerts: List<RequestAlert>)
}

/** Які запити вже показані. Приватне для акаунта: зникає з виходом, як і решта його стану. */
interface SeenRequestStore {
    fun seen(): Set<String>
    fun markSeen(keys: Set<String>)
}

/** Про що дзвонити. Чисте правило: без часу, без платформи. */
object RequestRules {
    /** Скільки ключів тримає сховище «бачили». Старіші відповіли або втратили актуальність. */
    const val SEEN_CAPACITY = 500

    /**
     * Сповіщення за [requests], яких нема в [seen], згруповані за подією. Назва береться з
     * [events]: без неї сповіщення нікуди не веде, тож такий запит пропускаємо до наступного
     * перечитування. Вимкнені сповіщення — порожній список; ключі при цьому все одно варто
     * позначити баченими, щоб увімкнення пізніше не дзвонило про давнє.
     */
    fun alerts(requests: List<JoinRequest>, seen: Set<String>, events: List<Event>, enabled: Boolean): List<RequestAlert> {
        if (!enabled) return emptyList()
        val titles = events.associate { it.id to it.title }
        return requests.asSequence()
            .filter { it.key !in seen }
            .groupBy { it.eventId }
            .mapNotNull { (eventId, fresh) ->
                val title = titles[eventId] ?: return@mapNotNull null
                RequestAlert(eventId, title, fresh.size)
            }
    }

    /** Скільки запитів чекає на кожну подію: для бейджів на головній. */
    fun pendingByEvent(requests: List<JoinRequest>): Map<String, Int> =
        requests.groupingBy { it.eventId }.eachCount()
}
