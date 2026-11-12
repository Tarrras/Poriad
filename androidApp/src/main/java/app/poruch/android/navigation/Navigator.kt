package app.poruch.android.navigation

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
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
        // Подвійний тап не кладе той самий екран двічі.
        if (key !is Tab) { if (stack.last() != key) stack.add(key); return }
        // Тап по вже відкритій вкладці — не перехід. За класом, не за рівністю: `Explore(focusId)` і
        // `Explore()` — та сама вкладка, інакше тап по «Мапа» після «На мапі» скидав екран і шторку.
        if (stack.size == 1 && stack.last()::class == key::class) return
        // Стек чистимо, а не тримаємо корені всіх вкладок: NavDisplay не показує перенесений запис.
        reset(key)
    }

    fun back() {
        PoruchLog.d("nav") { "back from ${describe()}" }
        if (stack.size > 1) stack.removeLastOrNull()
        // Корінь іншої вкладки — не кінець застосунку: «Назад» веде на головну, а вже з неї — назовні.
        else if (stack.last() !is Home) reset(Home)
    }

    /**
     * «Назад» з кореня не-головної вкладки належить застосунку. `NavDisplay` обробляє «Назад» лише коли під
     * записом є попередній, а `open(Tab)` лишає вкладку єдиним записом — тож без цього система закривала застосунок.
     */
    val handlesRootBack: Boolean get() = stack.size == 1 && stack.last() !is Home

    /** Замінює весь стек одним записом, напр. лист відновлення пароля веде на профіль. */
    fun reset(key: NavKey) {
        stack.clear(); stack.add(key)
        PoruchLog.d("nav") { "stack now ${describe()}" }
    }

    /** «+» питає одне: на подію з афіші чи своя зустріч (docs/creation-platform-plan-2026-11.md, етап 2). Шторку малює корінь. */
    var choosingCreate by mutableStateOf(false)
        private set

    /** «Створити» з будь-якого місця: спершу вибір. Редактор відкритий і гостю — вхід лише на «Опублікувати». */
    fun createEvent() { choosingCreate = true }

    /** Відповідь на вибір: [own] — редактор «Своя зустріч», false — афіша на мапі, де є «Хочу піти з компанією»; null — закрили. */
    fun chooseCreate(own: Boolean?) {
        choosingCreate = false
        when (own) {
            true -> open(Editor())
            false -> { app.createFromAfisha(); open(Explore()) }
            null -> Unit
        }
    }

    private fun describe() = stack.joinToString { it.label() }
    private fun NavKey.label() = when (this) {
        is Detail -> "Detail(${eventId.take(8)})"
        is Editor -> "Editor(${editingId?.take(8) ?: "new"})"
        is Chat -> "Chat(${eventId.take(8)})"
        is ArtistPage -> "ArtistPage(${artistId.take(8)})"
        is Explore -> if (focusId.isEmpty()) "Explore" else "Explore(${focusId.take(8)})"
        else -> this::class.simpleName ?: toString()
    }
}
