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

/**
 * Що робить «Поширити» (docs/organizers-1.5.md, 1.6, рішення власника 02.11 «за подією і роллю»): [PROMOTE] — «Поширити
 * анонс», «Пост для Threads» з посиланням для запису; [FRIEND] — «Поділитися з другом», особисте посилання `?by=`, як
 * «Покликати з собою». Сайт повторює ту саму умову.
 */
enum class ShareMode { PROMOTE, FRIEND }

object ShareRules {
    /**
     * Анонс поширює лише організатор власної звичайної спільнотної події. Усі інші діляться з другом: творець «Шукаю
     * компанію» (його збір — про чужу афішу), гість на чужій події, афіша. [me] — id акаунта, null — гість.
     */
    fun mode(event: Event, me: String?): ShareMode {
        val room = event.gathering
        return if (me != null && room != null && room.companionOf == null && room.organizerId == me) ShareMode.PROMOTE else ShareMode.FRIEND
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
    fun text(event: Event): String =
        text(event.id, event.displayTitle, event.startsAt, event.timeZone, event.placeLabel, event.blurb, event.description)

    /** Те саме з полів: щойно опублікована подія ([EventDraft]) ще не має картки. */
    fun text(id: String, title: String, startsAt: String, timeZone: String, place: String, blurb: String?, description: String): String {
        val zone = runCatching { TimeZone.of(timeZone) }.getOrDefault(TimeZone.UTC)
        val start = runCatching { Instant.parse(startsAt) }.getOrNull()?.toLocalDateTime(zone)
        val date = start?.let {
            "${WEEKDAYS[it.dayOfWeek.isoDayNumber - 1]}, ${it.dayOfMonth} ${MONTHS[it.monthNumber - 1]}, " +
                "${it.hour.toString().padStart(2, '0')}:${it.minute.toString().padStart(2, '0')}"
        }
        val text = description.trim()
        val about = blurb?.trim()?.takeIf { it.isNotEmpty() }
            ?: if (text.length <= ABOUT_MAX) text else text.take(ABOUT_MAX).trimEnd() + "…"
        return listOfNotNull(
            title + "\n" + listOfNotNull(date, place.takeIf { it.isNotBlank() }).joinToString(" · "),
            about.takeIf { it.isNotEmpty() },
            "Запис: " + EventLinks.url(id).removePrefix("https://")
        ).joinToString("\n\n")
    }

    private val WEEKDAYS = listOf("пн", "вт", "ср", "чт", "пт", "сб", "нд")
    private val MONTHS = listOf(
        "січня", "лютого", "березня", "квітня", "травня", "червня",
        "липня", "серпня", "вересня", "жовтня", "листопада", "грудня"
    )
}
