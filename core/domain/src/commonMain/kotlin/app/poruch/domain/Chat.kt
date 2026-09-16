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

/** Чат події: читання хвоста, запис, видалення. Сервер пускає організатора й підтверджених. */
interface EventChat {
    /** Хвіст чату; з [after] — лише пізніше за цей момент (ISO-8601). Старіші вгорі. */
    suspend fun messages(eventId: String, after: String? = null): List<ChatMessage>
    suspend fun send(eventId: String, body: String): String
    suspend fun delete(messageId: String)
}
