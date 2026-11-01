package app.poruch.domain

import kotlin.time.Instant
import kotlinx.datetime.DateTimeUnit
import kotlinx.datetime.TimeZone
import kotlinx.datetime.isoDayNumber
import kotlinx.datetime.plus
import kotlinx.datetime.toLocalDateTime

/** «Повторити» (docs/organizers-1.5.md, 1.5): щотижневий клуб не набирає подію наново. */
object EventRepeat {
    /**
     * Чернетка з власної спільнотної події, минулої чи майбутньої: усі поля, фото й відео. Дата й час — на тиждень
     * пізніше, і ще на тиждень, поки не в майбутньому; у поясі події, тож перехід на зимовий час не зсуває годину. Медіа
     * копіюються в теку нової події з публікацією ([DraftMedia.Copied]); стара обкладинка без медіа (подія до 1.5) — теж.
     * Афіша (без [Event.gathering]) чи зіпсований рядок — null.
     */
    fun draft(event: Event, now: Instant): EventDraft? {
        val room = event.gathering ?: return null
        val zone = runCatching { TimeZone.of(event.timeZone) }.getOrNull() ?: return null
        var start = event.startInstant ?: return null
        var end = event.endInstant ?: return null
        do {
            start = start.plus(1, DateTimeUnit.WEEK, zone)
            end = end.plus(1, DateTimeUnit.WEEK, zone)
        } while (start <= now)
        val media = event.media.ifEmpty { listOfNotNull(event.imageUrl?.let { EventMedia(MediaKind.PHOTO, it) }) }
        return EventDraft(
            title = event.title, description = event.description, category = event.category, city = event.city,
            address = event.address, latitude = event.latitude, longitude = event.longitude,
            startsAt = start.toString(), endsAt = end.toString(), timeZone = event.timeZone, capacity = room.capacity,
            // Обкладинка — з медіа: стара адреса з теки іншої події не пройшла б перевірку сервера.
            imageUrl = null, minAge = room.minAge, maxAge = room.maxAge, approvalRequired = room.approvalRequired,
            contactUrl = room.contactUrl, media = media.take(MediaRules.MAX_ITEMS).map { DraftMedia.Copied(it) }
        )
    }
}

/** «Пост для Threads» (docs/organizers-1.5.md, 1.5): той самий текст, що в кабінеті на вебі. */
object ThreadsPost {
    /** Скільки опису беремо, коли нема речення «що це». */
    const val ABOUT_MAX = 200

    /**
     * ```
     * {Назва}
     * {нд, 2 листопада, 19:00} · {Місце}
     *
     * {blurb або перші 200 символів опису}
     *
     * Запис: poriad.app/e/{id}
     * ```
     * Час — у поясі події. Порожній опис — без абзацу.
     */
    fun text(event: Event): String {
        val zone = runCatching { TimeZone.of(event.timeZone) }.getOrDefault(TimeZone.UTC)
        val start = event.startInstant?.toLocalDateTime(zone)
        val date = start?.let {
            "${WEEKDAYS[it.dayOfWeek.isoDayNumber - 1]}, ${it.dayOfMonth} ${MONTHS[it.monthNumber - 1]}, " +
                "${it.hour.toString().padStart(2, '0')}:${it.minute.toString().padStart(2, '0')}"
        }
        val description = event.description.trim()
        val about = event.blurb?.trim()?.takeIf { it.isNotEmpty() }
            ?: if (description.length <= ABOUT_MAX) description else description.take(ABOUT_MAX).trimEnd() + "…"
        return listOfNotNull(
            event.displayTitle + "\n" + listOfNotNull(date, event.placeLabel.takeIf { it.isNotBlank() }).joinToString(" · "),
            about.takeIf { it.isNotEmpty() },
            "Запис: " + EventLinks.url(event.id).removePrefix("https://")
        ).joinToString("\n\n")
    }

    private val WEEKDAYS = listOf("пн", "вт", "ср", "чт", "пт", "сб", "нд")
    private val MONTHS = listOf(
        "січня", "лютого", "березня", "квітня", "травня", "червня",
        "липня", "серпня", "вересня", "жовтня", "листопада", "грудня"
    )
}
