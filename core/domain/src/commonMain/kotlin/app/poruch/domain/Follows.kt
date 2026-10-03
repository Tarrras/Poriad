package app.poruch.domain

import kotlin.time.Duration.Companion.hours
import kotlin.time.Instant

/** На що стежать, як це називає `follows.target_kind`. */
enum class FollowKind(val key: String) {
    PLACE("place"), ORGANIZER("organizer"), ARTIST("artist");

    companion object {
        fun fromKey(key: String?): FollowKind? = entries.firstOrNull { it.key == key }
    }
}

/**
 * Підписка зі списку `my_follows`. Для закладу [city], [address] і координати — щоб відкрити його на мапі без
 * запиту; для організатора — [avatarUrl]; для артиста — [artistKind], якщо сервер його знає. [upcoming] — скільки подій попереду (прокат — одна).
 */
data class Follow(
    val kind: FollowKind,
    val targetId: String,
    val name: String,
    val city: String = "",
    val address: String = "",
    val latitude: Double? = null,
    val longitude: Double? = null,
    val avatarUrl: String? = null,
    val upcoming: Int = 0,
    val artistKind: ArtistKind? = null
) {
    /** Заклад для мапи. Null — це організатор або сервер не віддав координат. */
    val place: Place?
        get() = if (kind == FollowKind.PLACE && latitude != null && longitude != null) {
            Place(targetId, name, city, address, latitude, longitude, upcoming)
        } else null
}

/**
 * «Стежити» на закладі й на організаторі (docs/follows.md). Лише з акаунтом: пуш прив'язаний до токена
 * акаунта, а гостю сервер не дає гранту.
 */
interface Follows {
    suspend fun mine(): List<Follow>
    suspend fun follow(kind: FollowKind, targetId: String)
    suspend fun unfollow(kind: FollowKind, targetId: String)

    /** Майбутні події з підписок для головної, найближчі першими, тими самими картками, що [EventDiscovery.cards]. */
    suspend fun upcoming(): List<Event>
}

/** Афіша закладу, за яким стежать: усе, що потрібно правилам пуша. Сюди потрапляє лише те, що видно в афіші (жива, якісна). */
data class PlaceListing(
    val eventId: String,
    val placeId: String,
    val title: String,
    val startsAt: Instant,
    val endsAt: Instant,
    /** Коли рядок з'явився в базі (`events.created_at`), а не коли починається подія. */
    val createdAt: Instant
)

/**
 * Що піде в одному пуші про заклади: скільки нового, у скількох закладах, найзавантаженіший першим, і
 * до трьох найближчих подій для тексту. Один пуш на людину. [announced] — усе, про що цим пушем сказано
 * (і сеанси прокату, яких у тексті нема): більше воно новим не буде.
 */
data class PlacePush(
    val total: Int,
    val placeCount: Int,
    val places: List<PlaceShare>,
    val eventIds: List<String>,
    val announced: Set<String>
)

data class PlaceShare(val placeId: String, val count: Int)

/**
 * Правила підписок. `placePush`, `isNew` і `mayPushPlaces` застосунок не викликає: це виконуваний опис
 * серверних `private.notify_place_follows` і `private.followed_events`, які їх і виконують. Що рухається
 * там — рухається й тут; розбіжність зловлять [FollowRulesTest] і `supabase/tests/follows.sql`.
 * Решта (`canFollow…`, `followOnRating`) — правила самого застосунку.
 */
object FollowRules {
    /** Пуш про нові події закладів — не частіше ніж раз на добу на людину. Скасування, перенесення й чат ліміту не мають. */
    val PLACE_PUSH_INTERVAL = 24.hours

    /** Скільки подій називає пуш і скільки закладів рахує. */
    const val PUSH_EVENTS = 3
    const val PUSH_PLACES = 5

    /** Раз на добу: перший пуш вільний, далі — коли з попереднього минула доба. */
    fun mayPushPlaces(lastPush: Instant?, now: Instant) = lastPush == null || now - lastPush >= PLACE_PUSH_INTERVAL

    /**
     * Нове — те, що з'явилось після підписки, ще не скінчилось і про що людині ще не казали ([announced]).
     * Що не влізло в ліміт, лишається новим і їде наступним разом; про вже назване вдруге не кажемо.
     */
    fun isNew(listing: PlaceListing, followedAt: Instant, announced: Set<String>, now: Instant): Boolean =
        listing.endsAt > now && listing.createdAt > followedAt && listing.eventId !in announced

    /**
     * Пуш для однієї людини: [followedAt] — коли вона підписалась на кожен заклад (без підписки заклад
     * не рахується), [announced] — про які події їй уже казали, [lastPush] — коли їй востаннє йшов такий пуш,
     * [hasDevice] — чи є куди слати: без токена нічого не витрачається, нове чекає на пристрій. Прокат із
     * кількох сеансів — одна подія (та сама назва без урахування регістру й крайніх пробілів), від
     * найближчого сеансу. Null — казати нічого.
     */
    fun placePush(
        listings: List<PlaceListing>,
        followedAt: Map<String, Instant>,
        announced: Set<String>,
        lastPush: Instant?,
        hasDevice: Boolean,
        now: Instant
    ): PlacePush? {
        if (!hasDevice || !mayPushPlaces(lastPush, now)) return null
        val due = listings.filter { l -> followedAt[l.placeId]?.let { isNew(l, it, announced, now) } == true }
        val runs = due
            .groupBy { it.placeId to it.title.trim(' ').lowercase() }
            .map { (_, sessions) -> sessions.minWith(compareBy({ it.startsAt }, { it.eventId })) }
        if (runs.isEmpty()) return null
        val byPlace = runs.groupBy { it.placeId }.map { (id, list) -> Triple(id, list.size, list.minOf { it.startsAt }) }
            .sortedWith(compareBy({ -it.second }, { it.third }, { it.first }))
        return PlacePush(
            total = runs.size,
            placeCount = byPlace.size,
            places = byPlace.take(PUSH_PLACES).map { PlaceShare(it.first, it.second) },
            eventIds = runs.sortedWith(compareBy({ it.startsAt }, { it.eventId })).take(PUSH_EVENTS).map { it.eventId },
            announced = due.mapTo(mutableSetOf()) { it.eventId }
        )
    }

    /** Стежити за закладом можна, коли афіша знає його: у спільнотних подій місця нема. */
    fun canFollowPlace(event: Event) = event.placeId != null

    /** Стежити можна за тим, хто вже проводить події, і не за собою. */
    fun canFollowOrganizer(profile: Profile, isMe: Boolean) = !isMe && profile.organized > 0

    /**
     * Початковий стан перемикача «Стежити за організатором» у шторці оцінки. Нова оцінка — увімкнено:
     * людина щойно була в нього на події. Змінюєш оцінку — те, що є, щоб не підписати знову того, від кого
     * колись відписався.
     */
    fun followOnRating(alreadyFollowing: Boolean, alreadyRated: Boolean) = alreadyFollowing || !alreadyRated
}
