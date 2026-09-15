package app.poruch.android.navigation

import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.snapshots.SnapshotStateList
import androidx.navigation3.runtime.NavKey
import app.poruch.domain.PoruchLog
import app.poruch.shared.PoruchApp

/**
 * Стек навігації в retained-скоупі Activity: переживає поворот, після смерті процесу старт з
 * головної. Клас, а не функції композиції: ті захоплювали застарілий `route`, і вкладки ламались.
 */
class Navigator(private val app: PoruchApp) {
    val stack: SnapshotStateList<NavKey> = mutableStateListOf(Home)
    val current: NavKey get() = stack.last()

    /** Вкладка лишається коренем стека; все інше пушиться зверху. */
    fun open(key: NavKey) {
        PoruchLog.d("nav") { "open ${key.label()} from ${describe()}" }
        if (key !is Tab) { stack.add(key); return }
        // Тап по вже відкритій вкладці — не перехід.
        if (stack.size == 1 && stack.last() == key) return
        // Стек чистимо, а не тримаємо корені всіх вкладок: NavDisplay не показує перенесений запис.
        reset(key)
    }

    fun back() {
        PoruchLog.d("nav") { "back from ${describe()}" }
        if (stack.size > 1) stack.removeLastOrNull()
    }

    /** Замінює весь стек одним записом, напр. лист відновлення пароля веде на профіль. */
    fun reset(key: NavKey) {
        stack.clear(); stack.add(key)
        PoruchLog.d("nav") { "stack now ${describe()}" }
    }

    /** Гість замість дії бачить вхід. */
    fun requireAccount(action: () -> Unit) {
        if (app.state.value.signedIn) action() else open(Auth)
    }

    private fun describe() = stack.joinToString { it.label() }
    private fun NavKey.label() = when (this) {
        is Detail -> "Detail(${eventId.take(8)})"
        is Editor -> "Editor(${editingId?.take(8) ?: "new"})"
        is Explore -> if (focusId.isEmpty()) "Explore" else "Explore(${focusId.take(8)})"
        else -> this::class.simpleName ?: toString()
    }
}
