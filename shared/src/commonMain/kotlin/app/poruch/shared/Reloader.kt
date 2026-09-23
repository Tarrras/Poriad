package app.poruch.shared

/**
 * Перечитування після змін і повернення з фону. Мапа й «мої» — завжди разом; відкрита подія
 * окремо, бо її запити й учасники живуть поза стрічкою і їх знає лише сервер.
 */
internal class Reloader(private val discovery: DiscoveryEngine, private val library: UserLibrary) {
    /** Мапа й «мої події». Гість перечитує лише мапу. */
    fun lists() { discovery.refresh(); library.load() }

    /** Те саме плюс відкрита подія: за час у фоні могли прийти запити, відповіді й повідомлення. */
    fun all() { lists(); library.openEventId?.let { library.select(it, full = true) } }

    /** Повернення в застосунок: як [all], але свіжу видачу не перепитуємо. */
    fun resumed() { discovery.refreshIfStale(); library.load(); library.openEventId?.let { library.select(it, full = true) } }

    /**
     * Усе, чого могла торкнутися зміна [id]. Індекс міста (до 5000 подій) — лише з [index]: нова,
     * змінена чи скасована подія міняє сам індекс, а участь, черга чи оцінка — лише свою картку.
     * Відкриту подію — повним запитом: змінились учасники й членство.
     */
    fun changed(id: String, index: Boolean = false) {
        if (index) discovery.refresh()
        discovery.reloadCard(id); library.load()
        if (library.openEventId == id) library.select(id, full = true)
    }

    /** Чекає, поки доїде все, що запустив [all]. Збій не кидає: він уже в [AppState.notice]. */
    suspend fun awaitAll() { discovery.awaitSearch(); library.awaitList(); library.awaitDetail() }
}
