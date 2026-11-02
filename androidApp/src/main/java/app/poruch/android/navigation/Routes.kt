package app.poruch.android.navigation

import androidx.navigation3.runtime.NavKey
import kotlinx.serialization.Serializable

// Маршрути. Ключ несе аргументи типізовано: деталі без id не зібрати, редактор без нього — нова подія.

/** Корені вкладок. Стек тримає рівно один такий запис знизу. */
sealed interface Tab : NavKey

@Serializable data object Home : Tab
/** Не «Map» через `kotlin.collections.Map`. [focusId] наводить мапу на пін події. */
@Serializable data class Explore(val focusId: String = "") : Tab
@Serializable data object Mine : Tab
@Serializable data object Profile : Tab

/** [requests] — «Запити · N» з головної: деталі одразу прокручуються до запитів, вони внизу сторінки. */
@Serializable data class Detail(val eventId: String, val requests: Boolean = false) : NavKey
/** Екран артиста: що показувати, тримає [app.poruch.shared.AppState.artist]; хто відкриває, кличе `openArtist` перед переходом. */
@Serializable data class ArtistPage(val artistId: String) : NavKey
/** Без [editingId] — нова подія; [repeatOf] — нова з полями, фото й відео власної події («Повторити»). */
@Serializable data class Editor(val editingId: String? = null, val repeatOf: String? = null) : NavKey
/** Чат події. Лише для організатора й учасників: іншим сервер віддасть порожньо. */
/** Чат події; з [thread] (хто питає) — розмова «Запитати організатора». */
@Serializable data class Chat(val eventId: String, val thread: String? = null) : NavKey
/** Вхід і реєстрація. [reason] — з якою дією прийшов гість: від неї підзаголовок. */
@Serializable data class Auth(val reason: AuthReason = AuthReason.GENERAL) : NavKey

/** Навіщо гість опинився на вході: підзаголовок каже, навіщо профіль саме зараз. Двійник `AuthReason` на iOS. */
@Serializable enum class AuthReason(
    /** `action` для `auth_wall`: гість вперся саме в цю дію. Зайшов сам — не стіна. `create` рахує сам `createEvent`. */
    val wall: String?
) { GENERAL(null), CREATE(null), JOIN("join"), FOLLOW("follow"), COMPANY("companion") }
/** Підписки: заклади й організатори, за якими стежить людина. З профілю й з головної. */
@Serializable data object Follows : NavKey
/** «Мої місця»: райони й кола, про нові зустрічі в яких скажемо пушем. З профілю. */
@Serializable data object MyPlaces : NavKey
/** «Подію створено» після публікації (1.6): що показати — у спільному стані, тож без аргументів. */
@Serializable data object Published : NavKey
/** Лист відновлення відкрив застосунок: окремий екран для нового пароля, поверх стека. */
@Serializable data object NewPassword : NavKey
