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

@Serializable data class Detail(val eventId: String) : NavKey
@Serializable data class Editor(val editingId: String? = null) : NavKey
/** Чат події. Лише для організатора й учасників: іншим сервер віддасть порожньо. */
@Serializable data class Chat(val eventId: String) : NavKey
@Serializable data object Auth : NavKey
