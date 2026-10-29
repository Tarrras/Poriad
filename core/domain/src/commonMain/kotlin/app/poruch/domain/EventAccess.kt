package app.poruch.domain

/**
 * Доступ до подій, розбитий на п'ять інтерфейсів за правами на сервері: читати може будь-хто,
 * зберігати — власник списку, створювати й скасовувати — організатор, приєднуватись — гість,
 * відповідати на запити — знову організатор. Так екран бачить лише те, що йому справді треба,
 * а тестова підробка реалізує два методи, а не двадцять.
 */
data class EventQuery(
    val south: Double, val west: Double, val north: Double, val east: Double,
    val category: EventCategory? = null, val from: String? = null, val to: String? = null,
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

    /** Останні «Мої події» з телефону, щоб план було видно без мережі. Null — ще не читали з цим акаунтом. */
    fun cachedMine(): CachedMine? = null

    /** Учасники події. Бачать лише організатор і учасники, решта отримує порожній список. */
    suspend fun attendees(id: String): List<Attendee>

    /**
     * Заклади, в назві чи адресі яких є слово з префіксом [text], лише з майбутніми подіями,
     * найживіші першими. Без [bounds] — усюди, з [city] — у місті.
     */
    suspend fun searchPlaces(text: String, city: String? = null, bounds: EventQuery? = null): List<Place>

    /** Майбутні події закладу від найближчої, тими самими картками, що [cards]. */
    suspend fun placeEvents(placeId: String): List<Event>

    /** Артисти, в імені яких є слово з префіксом [text], лише з майбутніми подіями, найживіші першими. З [city] — у місті. */
    suspend fun searchArtists(text: String, city: String? = null): List<ArtistHit>

    /** Майбутні події артиста від найближчої, тими самими картками, що [cards]. */
    suspend fun artistEvents(artistId: String): List<Event>

    /** «Ваші артисти» (docs/artist-radar.md): що в місті [city] і де ще. Сервер без радару — порожньо. */
    suspend fun artistRadar(ids: List<String>, city: String?): List<ArtistRadar> = emptyList()

    /** «За ким стежити?»: хто їде в [city], найбільше вечорів попереду першими; без міста — хто гастролює країною. */
    suspend fun popularArtists(city: String?): List<PopularArtist> = emptyList()

    /** Укриття поруч і комендантська міста для блоку «Безпека». Null — подію не видно. */
    suspend fun safety(id: String): EventSafety?

    /** Хто шукає компанію на афішу [parentId]: картки супутників без імен, найближча зустріч першою. */
    suspend fun companions(parentId: String): List<CompanionCard>

    /**
     * Тизер «Хочу піти з компанією» на афішу [eventId]: скільки, вік кошиками, спільне (docs/return-hooks.md).
     * Сервер без міграції — null.
     */
    suspend fun companyTeaser(eventId: String): CompanyTeaser? = null

    /** Люди з наміром на [eventId]. Порожньо, поки в мене самого наміру нема. */
    suspend fun companyPeople(eventId: String): List<CompanyPerson> = emptyList()

    /** Хто кличе на [eventId] за токеном з посилання. Null — токен чужий, протух чи подію вже не видно (docs/invites.md). */
    suspend fun inviter(token: String, eventId: String): Inviter?

    /** Райони [city] з межами: пошук і фільтр мапи рахує клієнт. Сервер без міграції районів — порожньо. */
    suspend fun districts(city: String): List<District>

    /** Скидає кеш попереднього акаунта. Викликати при зміні користувача. */
    fun clearPrivateCache()
}

/** Останні відповіді «Моїх подій» на телефоні: події, закладки й черга, з яких складаються розрізи. */
data class CachedMine(val events: List<Event>, val savedIds: List<String>, val waitlistedIds: List<String>)

/** Закладки. Приватний список, якого не бачить ніхто, крім власника. */
interface SavedEvents {
    suspend fun savedIds(): List<String>
    suspend fun save(id: String)
    suspend fun unsave(id: String)

    /** Закладки гостя після входу (docs/guest-saves.md). Повтор уже збереженої — не помилка. */
    suspend fun saveAll(ids: List<String>) = ids.forEach { save(it) }
}

/**
 * Закладки гостя: лише на телефоні, доки людина не ввійде (docs/guest-saves.md). Після входу переходять в акаунт і
 * стираються, тож закладки акаунта сюди ніколи не потрапляють.
 */
interface GuestSavedStore {
    fun ids(): List<String>
    fun write(ids: List<String>)
}

/** Свої події: створити, змінити, скасувати. Сервер віддає це лише організаторові. */
interface EventAuthoring {
    suspend fun create(id: String, draft: EventDraft): String
    suspend fun update(id: String, draft: EventDraft): String
    suspend fun cancel(id: String)
    /** Супутник «Йдемо разом» на афішу [parentId]. Повтор повертає вже створений. */
    suspend fun createCompanion(parentId: String, meetAt: String, note: String?, capacity: Int): String
    /** Новий час збору [id] (R7б); відповідає й на питання після переносу афіші (R7а). */
    suspend fun moveCompanion(id: String, meetAt: String)
    suspend fun uploadImage(eventId: String, bytes: ByteArray, contentType: String): String
    /** Прибирає завантажене фото, яке так і не стало фото події. За замовчуванням нічого. */
    suspend fun deleteImage(url: String) {}
    /** Скільки людей стежать за зоною з цією точкою (docs/my-places.md); null — менше трьох. */
    suspend fun zoneAudience(latitude: Double, longitude: Double): Int? = null
}

/** Участь: двері й черга під ними. */
interface EventParticipation {
    suspend fun join(id: String)
    suspend fun leave(id: String)

    /** Події, де цей акаунт у черзі. */
    suspend fun waitlistIds(): List<String>
    suspend fun joinWaitlist(id: String)
    suspend fun leaveWaitlist(id: String)

    /** Токен «Покликати з собою» на подію [id]: той самий для тієї ж людини й події (docs/invites.md). */
    suspend fun invite(id: String): String

    /** Намір «Хочу піти з компанією» на афішу [id]. Повертає, скільки інших уже хоче піти. */
    suspend fun setCompanyIntent(id: String, on: Boolean): Int = 0

    /** «Піти разом» з [userId] на афішу [id]. */
    suspend fun companyYes(id: String, userId: String): CompanyMatch = CompanyMatch(matched = false, companionId = null)

    /** Оцінки завершеної події: організаторові всі, учасникові — своя. */
    suspend fun ratings(id: String): List<EventRating>
    suspend fun rate(id: String, score: Int, comment: String?, tags: List<RatingTag>)

    /** Мої бали за id події: «Мої події» знають, де ще «Оцінити». Сервер без міграції — порожньо. */
    suspend fun myRatings(): Map<String, Int> = emptyMap()
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
