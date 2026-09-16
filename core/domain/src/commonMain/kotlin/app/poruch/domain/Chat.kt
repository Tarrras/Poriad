package app.poruch.domain

/** Повідомлення в чаті події, як його віддає `event_messages`. [createdAt] — ISO-8601. */
data class ChatMessage(
    val id: String,
    val eventId: String,
    val authorId: String,
    val authorName: String,
    val avatarUrl: String?,
    val body: String,
    val createdAt: String
)

/** Ліміти чату. Сервер перевіряє ті самі. */
object ChatRules {
    const val MAX_BODY = 2000

    /** Скільки повідомлень тягне перше відкриття. Старішого не догортаємо: чат про одну зустріч, а не архів. */
    const val PAGE = 100

    /** Пауза між перечитуваннями, поки екран відкритий. Без сокетів: розмова перед подією, а не месенджер. */
    const val POLL_INTERVAL_MS = 5_000L

    /** Що зберігаємо: обрізане. Порожнє — нема чого слати. */
    fun normalize(text: String): String = text.trim()
    fun isBody(text: String) = normalize(text).length in 1..MAX_BODY

    /**
     * Зливає відомі повідомлення з дозавантаженими: без дублів, за часом, потім за id, як на
     * сервері. Видалені зникають лише при повному перечитуванні, це прийнятно.
     */
    fun merge(known: List<ChatMessage>, fresh: List<ChatMessage>): List<ChatMessage> {
        if (fresh.isEmpty()) return known
        val byId = LinkedHashMap<String, ChatMessage>(known.size + fresh.size)
        known.forEach { byId[it.id] = it }
        fresh.forEach { byId[it.id] = it }
        return byId.values.sortedWith(compareBy({ it.createdAt }, { it.id }))
    }
}

/** Непрочитане в чаті однієї події, як його віддає `my_chat_unread`: скільки і що останнє. */
data class ChatUnread(
    val eventId: String,
    val eventTitle: String,
    val unread: Int,
    val lastMessageId: String,
    val lastAuthorName: String,
    val lastBody: String,
    val lastAt: String
)

/** Сповіщення про нові повідомлення в одній події. */
data class ChatAlert(val eventId: String, val eventTitle: String, val count: Int, val authorName: String, val preview: String)

/** Показує сповіщення про повідомлення негайно. Реалізує платформа, зазвичай той самий клас, що й [RequestNotifier]. */
interface ChatNotifier {
    /** Не `notify`: разом із [RequestNotifier] в одному класі Swift плутав би підписи. */
    fun notifyMessages(alerts: List<ChatAlert>)
}

/** Чат події: читання хвоста, запис, видалення. Сервер пускає організатора й підтверджених. */
interface EventChat {
    /** Хвіст чату; з [after] — лише пізніше за цей момент (ISO-8601). Старіші вгорі. */
    suspend fun messages(eventId: String, after: String? = null): List<ChatMessage>
    suspend fun send(eventId: String, body: String): String
    suspend fun delete(messageId: String)

    /** Події з непрочитаним, свіжіші першими. Сервер без міграції — порожній список. */
    suspend fun unread(): List<ChatUnread>

    /** Прочитано до зараз. */
    suspend fun markRead(eventId: String)
}

/** Про що дзвонити з чатів. Чисте правило, як [RequestRules]. */
object ChatAlertRules {
    /**
     * Сповіщення за подіями, чиє останнє повідомлення ще не бачили. Відкритий чат ([openEventId])
     * пропускаємо: людина і так дивиться на нього.
     */
    fun alerts(unread: List<ChatUnread>, seen: Set<String>, openEventId: String?, enabled: Boolean): List<ChatAlert> {
        if (!enabled) return emptyList()
        return unread.filter { it.eventId != openEventId && it.lastMessageId !in seen }
            .map { ChatAlert(it.eventId, it.eventTitle, it.unread, it.lastAuthorName, it.lastBody.take(PREVIEW)) }
    }

    /** Скільки знаків повідомлення показує сповіщення. */
    const val PREVIEW = 120
}
