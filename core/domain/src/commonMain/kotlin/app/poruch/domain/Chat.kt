package app.poruch.domain

/** Повідомлення в чаті події, як його віддає `event_messages`. [createdAt] — ISO-8601. */
data class ChatMessage(
    val id: String,
    val eventId: String,
    val authorId: String,
    val authorName: String,
    val avatarUrl: String?,
    val body: String,
    val createdAt: String,
    /** У повідомленні реквізити для оплати: під ним — застереження й «Поскаржитись». */
    val paymentDetails: Boolean = false,
    /** Скріншот оплати: шлях у приватному сховищі. */
    val image: String? = null
)

/** Ліміти чату. Сервер перевіряє ті самі. */
object ChatRules {
    const val MAX_BODY = 2000

    /** Скільки повідомлень тягне перше відкриття. Старішого не догортаємо: чат про одну зустріч, а не архів. */
    const val PAGE = 100

    /** Пауза між перечитуваннями, поки екран відкритий. Без сокетів: розмова перед подією, а не месенджер. */
    const val POLL_INTERVAL_MS = 5_000L

    /** Підпис скріншота без тексту: сервер вимагає текст, і старі збірки хоча б скажуть, що картинка була. */
    const val PROOF_BODY = "Скріншот оплати"

    /** Довша сторона скріншота: досить, щоб прочитати суму й імʼя в банківській квитанції. */
    const val PROOF_SIDE = 2048

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

/**
 * Чат події: читання хвоста, запис, видалення. Загальний чат сервер пускає організатора й підтверджених; з [thread]
 * (id того, хто питає) — розмова «Запитати організатора» на двох: він і організатор.
 */
interface EventChat {
    /** Хвіст чату; з [after] — лише пізніше за цей момент (ISO-8601). Старіші вгорі. */
    suspend fun messages(eventId: String, after: String? = null, thread: String? = null): List<ChatMessage>
    /** [image] — шлях скріншота оплати з [uploadProof]. */
    suspend fun send(eventId: String, body: String, thread: String? = null, image: String? = null): String
    suspend fun delete(messageId: String)

    /** Скріншот оплати (JPEG) у приватне сховище; повертає шлях для [send]. */
    suspend fun uploadProof(eventId: String, jpeg: ByteArray): String

    /** Скріншот оплати зі сховища: бачать лише той, хто надіслав, і організатор. */
    suspend fun proof(path: String): ByteArray

    /** Події з непрочитаним у загальному чаті, свіжіші першими. Сервер без міграції — порожній список. */
    suspend fun unread(): List<ChatUnread>

    /** Прочитано до зараз. */
    suspend fun markRead(eventId: String, thread: String? = null)

    /** Розмови з організатором: організатору — усі, тому, хто питав, — своя. Сервер без міграції — порожньо. */
    suspend fun questions(eventId: String): List<QuestionThread>
}

/** Розмова «Запитати організатора» з `event_questions`: хто питає, останнє повідомлення й непрочитане. */
data class QuestionThread(
    val askerId: String,
    val askerName: String,
    val askerAvatar: String?,
    val lastBody: String,
    val lastAt: String,
    /** Останнє написав я: організатор уже відповів або я чекаю відповіді. */
    val lastMine: Boolean,
    val unread: Int
)

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
