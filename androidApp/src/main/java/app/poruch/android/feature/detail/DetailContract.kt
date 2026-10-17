package app.poruch.android.feature.detail

import app.poruch.android.navigation.AuthReason
import app.poruch.domain.Artist
import app.poruch.domain.Shelter
import app.poruch.domain.Event
import app.poruch.domain.RatingTag
import app.poruch.domain.ReportReason
import app.poruch.shared.DetailScreenState

/**
 * Стан деталей: [screen] згортає спільний стор [app.poruch.shared.DetailPresenter] — одна згортка на обидві
 * платформи; тут лише листи й прапорці цього екрана на цьому пристрої.
 */
data class DetailState(
    val screen: DetailScreenState = DetailScreenState.Empty,
    /** Потяг вниз у дорозі. */
    val refreshing: Boolean = false,
    val confirmingCancel: Boolean = false,
    val reporting: ReportTarget? = null,
    val confirmingBlock: Boolean = false,
    /** Попередження перед виходом у чужий чат: спершу кажемо, куди й хто це додав. */
    val confirmingContact: Boolean = false,
    /** Відкрита шторка створення супутника. */
    val seekingCompany: Boolean = false
)

/** На що скарга: на подію, на того, хто її опублікував, чи на людину з картки. */
enum class ReportTarget { EVENT, ORGANIZER, PERSON }

sealed interface DetailIntent {
    data object Back : DetailIntent
    /** Відповідь системи на [DetailEffect.AskNotificationPermission]. */
    data class NotificationPermissionAnswered(val granted: Boolean) : DetailIntent
    /** Потяг вниз: перечитати місця, членство й запити. */
    data object Refresh : DetailIntent
    /** Інша дата в каруселі прокату. */
    data class PickSession(val id: String) : DetailIntent
    /** Інша подія цього місця: окремий екран поверх, щоб «назад» повертало сюди. */
    data class OpenEvent(val id: String) : DetailIntent
    /** Артист зі складу: його екран поверх. */
    data class OpenArtist(val artist: Artist) : DetailIntent
    /** Маршрут до укриття в системних мапах. */
    data class OpenShelter(val shelter: Shelter) : DetailIntent
    /** «Шукаю компанію»: шторка створення супутника. Гостя веде на вхід. */
    data class SeekCompany(val open: Boolean) : DetailIntent
    /** [meetAt] — з [app.poruch.domain.CompanionRules.meetTimes]. */
    data class CreateCompanion(val meetAt: String, val note: String, val capacity: Int) : DetailIntent
    /** Запит у чужий супутник прямо з картки. */
    data class JoinCompanion(val id: String) : DetailIntent
    /** Екран знову зверху після іншого екрана деталей: той перебрав єдиний слот відкритої події. */
    data object Reopen : DetailIntent
    /** «Стежити» / «Ви стежите» на закладі афіші. Гостя веде на вхід. */
    data object ToggleFollowPlace : DetailIntent
    /** Те саме на картці людини: [name] — для списку підписок, поки сервер не віддав повні дані. */
    data class ToggleFollowPerson(val userId: String, val name: String) : DetailIntent
    data object PrimaryAction : DetailIntent
    data object ToggleSaved : DetailIntent
    data object Share : DetailIntent
    data object AddToCalendar : DetailIntent
    data object OpenInMaps : DetailIntent
    /** Тап у міні-мапу: та сама подія на великій мапі. */
    data object OpenMap : DetailIntent
    /** «Читати повністю на джерелі»: те саме посилання з-під опису. */
    data object OpenSource : DetailIntent
    data object Edit : DetailIntent
    data class ConfirmCancel(val open: Boolean) : DetailIntent
    data class ShowReport(val target: ReportTarget?) : DetailIntent
    /** Ціль їде всередині: шторка спершу закривається (і скидає [DetailState.reporting]), а вже потім шле це. */
    data class SendReport(val target: ReportTarget, val reason: ReportReason, val details: String) : DetailIntent
    data class ConfirmBlock(val open: Boolean) : DetailIntent
    data object BlockOrganizer : DetailIntent
    /** Відкрити чат учасників: спершу попередження, потім браузер. */
    data class ConfirmContact(val open: Boolean) : DetailIntent
    data object OpenContact : DetailIntent
    /** Чат події всередині застосунку. */
    data object OpenChat : DetailIntent
    /** Картка людини: організатор, учасник чи той, хто проситься. Гостя веде на вхід. */
    data class OpenPerson(val userId: String) : DetailIntent
    data object ClosePerson : DetailIntent
    data class BlockPerson(val userId: String) : DetailIntent
    data class ReportPerson(val userId: String) : DetailIntent
    data class ApproveRequest(val userId: String) : DetailIntent
    data class DeclineRequest(val userId: String) : DetailIntent
    data object CancelEvent : DetailIntent
    /** [follow] — що показував перемикач «Стежити за організатором»; null — перемикача не було. */
    data class Rate(val score: Int, val comment: String, val tags: List<RatingTag>, val follow: Boolean? = null) : DetailIntent
    data class AttachPhoto(val bytes: ByteArray, val contentType: String) : DetailIntent {
        // Масиви байтів порівнюються за посиланням: два вибори того самого файлу — різні інтенти.
        override fun equals(other: Any?) = this === other ||
            (other is AttachPhoto && contentType == other.contentType && bytes.contentEquals(other.bytes))
        override fun hashCode() = 31 * bytes.contentHashCode() + contentType.hashCode()
    }
}

sealed interface DetailEffect {
    data object Back : DetailEffect
    data class Edit(val id: String) : DetailEffect
    /** Гість тапнув дію, що потребує профілю; [reason] каже екрану входу, яку саме. */
    data class RequireSignIn(val reason: AuthReason = AuthReason.GENERAL) : DetailEffect
    /** Приєднались, а нагадування ще не ввімкнені: питаємо дозвіл системи, маршрут повертає відповідь у [DetailIntent.NotificationPermissionAnswered]. */
    data object AskNotificationPermission : DetailEffect
    data class ShareEvent(val event: Event) : DetailEffect
    data class OpenCalendar(val event: Event) : DetailEffect
    data class OpenMaps(val event: Event) : DetailEffect
    data class OpenShelter(val shelter: Shelter) : DetailEffect
    /** Супутник створено: «Поділитися» з посиланням на нього і назвою афіші. */
    data class ShareCompanion(val parent: Event, val companionId: String) : DetailEffect
    /** Сторінка джерела афіші в браузері. */
    data class OpenLink(val url: String) : DetailEffect
    /** Наша власна мапа, наведена на цю подію. */
    data class OpenMap(val id: String) : DetailEffect
    data class OpenChat(val id: String) : DetailEffect
    data class OpenEvent(val id: String) : DetailEffect
    data class OpenArtist(val id: String) : DetailEffect
}
