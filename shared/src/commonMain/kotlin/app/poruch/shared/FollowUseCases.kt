package app.poruch.shared

import app.poruch.domain.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * «Стежити» на закладі й організаторі (docs/follows.md). Кнопка перемикається одразу, а запит іде
 * окремо, як у закладки: при збої повертаємо як було й кажемо про помилку. Лише з акаунтом: гостя ведемо
 * на вхід, як у `join`.
 */
internal class FollowUseCases(
    private val follows: Follows?,
    private val events: EventDiscovery,
    private val store: AppStore,
    private val library: UserLibrary,
    private val discovery: DiscoveryEngine
) {
    /** Запити на сервер — по черзі: швидкі «Стежити» і «Не стежити» не мають розминутись на дорозі. */
    private val serial = Mutex()

    fun set(kind: FollowKind, targetId: String, name: String, following: Boolean) {
        if (!store.value.signedIn) return store.failed(AppError.SessionRequired, byPerson = true)
        val repository = follows ?: return store.failed(AppError.ServiceUnavailable, byPerson = true)
        if (store.value.isFollowing(kind, targetId) == following) return
        change(repository, kind, targetId, name, following, report = true)
    }

    /**
     * Підписка з шторки оцінки. Оцінку вже надіслано, і збій підписки її не псує: кнопка просто повертається як була,
     * без помилки для людини.
     */
    fun afterRating(organizerId: String, name: String, following: Boolean) {
        val repository = follows ?: return
        if (!store.value.signedIn || store.value.isFollowing(FollowKind.ORGANIZER, organizerId) == following) return
        change(repository, FollowKind.ORGANIZER, organizerId, name, following, report = false)
    }

    private fun change(repository: Follows, kind: FollowKind, targetId: String, name: String, following: Boolean, report: Boolean) {
        PoruchLog.i("action") { "follow ${kind.key} ${targetId.shortId()} on=$following" }
        val uid = store.value.session.userId
        // Що було: відкат відписки повертає підписку з її даними (місто, координати, фото), а не голе ім'я.
        val before = store.value.library.follows.firstOrNull { it.kind == kind && it.targetId == targetId }
        library.setFollow(kind, targetId, name, following)
        library.followStarted()
        store.scope.launch {
            try {
                serial.withLock { send(repository, kind, targetId, following) }
                if (following && store.value.session.userId == uid) library.followMade()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                val error = e.asAppError()
                PoruchLog.w("action") { "follow ${kind.key} failed: $error" }
                // Інший акаунт уже бачить свій стан: чужий збій йому нічого не каже.
                if (store.value.session.userId == uid) {
                    // Назад лише якщо з того часу ніхто не перемкнув: інакше відкотили б чужу зміну.
                    if (store.value.isFollowing(kind, targetId) == following) library.setFollow(kind, targetId, name, !following, before)
                    if (report) store.failed(error, byPerson = true)
                }
            } finally {
                library.followFinished()
            }
        }
    }

    private suspend fun send(repository: Follows, kind: FollowKind, targetId: String, following: Boolean) {
        if (following) {
            repository.follow(kind, targetId)
            // Метрика лише про успішну підписку: чи є на що повертати людей (docs/analytics.md).
            PoruchAnalytics.track("follow", "target" to kind.key)
        } else repository.unfollow(kind, targetId)
    }

    /**
     * Тап по пушу про кілька подій закладу: мапа переходить до нього й відкриває його стос. Заклад беремо з
     * підписок, а коли їх ще не завантажено (холодний старт) — з карток його подій.
     */
    fun openPlace(placeId: String) {
        store.scope.launch {
            val known = store.value.library.follows.firstOrNull { it.kind == FollowKind.PLACE && it.targetId == placeId }?.place
            val place = known ?: try {
                placeFrom(placeId, events.placeEvents(placeId))
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                PoruchLog.w("action") { "open place failed: ${e.asAppError()}" }
                null
            }
            if (place != null) discovery.focusPlace(place) else store.failed(AppError.EventUnavailable)
        }
    }

    private fun placeFrom(placeId: String, cards: List<Event>): Place? =
        cards.firstOrNull { it.placeId == placeId }?.let {
            Place(placeId, it.placeName ?: it.placeLabel, it.city, it.address, it.latitude, it.longitude, cards.size)
        }
}
