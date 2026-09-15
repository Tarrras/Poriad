package app.poruch.domain

import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime
import kotlin.time.Instant

/**
 * Прокат — одна картка, скільки б сеансів у ньому не було: без згортання близько чверті стрічки
 * була б тим самим рядком з іншою датою.
 *
 * На відміну від [DuplicateEvents], сеанси не дублікати: на кожен окремий квиток. Тому вони не
 * ховаються, а збираються в [EventIndexEntry.sessions]: картка показує найближчий, екран деталей
 * дає вибір дати. У базі нічого не зливається, збережена подія вказує на конкретний вечір.
 *
 * Викликати після [DuplicateEvents.fold], інакше той самий сеанс від двох продавців стане двома
 * сеансами прокату.
 */
object EventSeries {

    /** Збирає сеанси прокату в одну картку. Представник — найраніший сеанс, решта в `sessions` за часом. */
    fun fold(events: List<EventIndexEntry>): List<EventIndexEntry> {
        if (events.size < 2) return events

        val groups = LinkedHashMap<Long, MutableList<EventIndexEntry>>()
        for (event in events) {
            val place = event.seriesPlace() ?: continue
            groups.getOrPut(place) { mutableListOf() } += event
        }
        if (groups.values.none { it.size > 1 }) return events

        val primaries = HashMap<String, EventIndexEntry>()
        val absorbed = HashSet<String>()
        for (bucket in groups.values) {
            if (bucket.size == 1) continue
            for (run in bucket.runs()) {
                if (run.size == 1) continue
                val ordered = run.sortedWith(compareBy({ it.startsAtInstant() }, { it.id }))
                val primary = ordered.first()
                primaries[primary.id] = primary.copy(
                    sessions = ordered.map { EventSession(it.id, it.startsAt, it.timeZone) })
                ordered.drop(1).forEach { absorbed += it.id }
            }
        }
        if (primaries.isEmpty()) return events
        return events.mapNotNull { event ->
            when {
                event.id in absorbed -> null
                else -> primaries[event.id] ?: event
            }
        }
    }

    /**
     * Сеанси прокату для каруселі на екрані деталей, за часом. Порожньо, якщо вибору немає.
     *
     * Скасований сеанс в індекс не потрапляє, тож за id його прокат не знайти. Такий (відкритий,
     * наприклад, зі «Збережених») зводимо до прокату за тим самим ключем, що й [fold]: місце
     * плюс зведена назва, і показуємо в каруселі позначеним.
     *
     * Карусель показує лише те, що є в поточному індексі: під фільтром «Сьогодні» будуть
     * сьогоднішні сеанси. Окремий запит на кожне відкриття того не вартий.
     */
    fun sessionsOf(event: Event, index: List<EventIndexEntry>): List<EventSession> {
        val own = EventSession(event.id, event.startsAt, event.timeZone, cancelled = event.isCancelled)
        index.firstOrNull { run -> run.sessions.any { it.id == event.id } }?.let { run ->
            return run.sessions.map { if (it.id == event.id) own else it }
        }
        val target = event.asIndexEntry()
        if (target.isCommunity || target.startsAtInstant() == null) return emptyList()
        val tokens = with(DuplicateEvents) { target.title.tokens() }
        if (tokens.isEmpty()) return emptyList()
        val place = MapPins.placeOf(target)
        val siblings = index.filter { entry ->
            entry.id != event.id && !entry.isCommunity && MapPins.placeOf(entry) == place &&
                with(DuplicateEvents) { entry.title.tokens() } == tokens
        }.flatMap { entry ->
            entry.sessions.ifEmpty { listOf(EventSession(entry.id, entry.startsAt, entry.timeZone)) }
        }
        if (siblings.isEmpty()) return emptyList()
        return (siblings + own).distinctBy { it.id }
            .sortedWith(compareBy({ it.startInstant?.epochSeconds ?: Long.MAX_VALUE }, { it.id }))
    }

    /** Скільки днів у прокаті, крім першого. День рахуємо в поясі сеансу, а не в UTC. */
    fun otherDays(sessions: List<EventSession>): Int {
        if (sessions.size < 2) return 0
        val days = sessions.mapNotNullTo(HashSet()) { session ->
            runCatching {
                Instant.parse(session.startsAt).toLocalDateTime(TimeZone.of(session.timeZone)).date
            }.getOrNull()
        }
        return maxOf(days.size - 1, 0)
    }

    /** Ключ місця або null для того, що не збирається: кімнати спільноти й нерозбірного часу. */
    private fun EventIndexEntry.seriesPlace(): Long? {
        if (isCommunity) return null
        if (startsAtInstant() == null) return null
        val place = MapPins.placeOf(this)
        return place.latitude * 1_000_003L + place.longitude
    }

    private fun EventIndexEntry.startsAtInstant(): Long? =
        runCatching { Instant.parse(startsAt) }.getOrNull()?.epochSeconds

    /**
     * Розбиває події однієї точки на прокати за точним збігом зведеної назви. Порога схожості
     * немає навмисно: вкладеність з [DuplicateEvents.similarity] зліпила б «Feels Garden Beer #9»
     * і «O.Torvald на Feels Garden Beer #9» в один прокат і сховала б справжній концерт.
     * Зведення назви спільне з [DuplicateEvents], тож «Балет "Баядерка"» і «Баядерка (ОНАТОБ)» —
     * один прокат.
     */
    private fun List<EventIndexEntry>.runs(): List<List<EventIndexEntry>> {
        val runs = LinkedHashMap<Set<String>, MutableList<EventIndexEntry>>()
        val alone = mutableListOf<List<EventIndexEntry>>()
        for (event in sortedBy { it.id }) {
            val tokens = with(DuplicateEvents) { event.title.tokens() }
            // Назва без токенів («Концерт», «Шоу») не збирається ні з чим.
            if (tokens.isEmpty()) alone += listOf(event)
            else runs.getOrPut(tokens) { mutableListOf() } += event
        }
        return runs.values.toList() + alone
    }
}
