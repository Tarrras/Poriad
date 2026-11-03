package app.poruch.domain

import kotlin.time.Instant
import kotlinx.datetime.DateTimeUnit
import kotlinx.datetime.TimeZone
import kotlinx.datetime.isoDayNumber
import kotlinx.datetime.plus
import kotlinx.datetime.toLocalDateTime

/** Чернетка правки власної спільнотної події: її будує спільний шар, щоб жоден редактор не забув [EventDraft.mediaBase]. */
object EventEdit {
    /**
     * Усі поля події. Медіа — як у події, а стара обкладинка без медіа (подія до 1.5) — першим фото, щоб її було видно в
     * «Фото й відео». [EventDraft.mediaBase] — ці файли, лише якщо медіа повні ([Event.mediaLoaded]): з картки — null.
     * [EventDraft.imageUrl] — обкладинка події: вона потрібна, коли платформа шле правку без медіа (`media = null`).
     * Афіша чи зіпсований рядок — null.
     */
    fun draft(event: Event): EventDraft? {
        val room = event.gathering ?: return null
        val media = event.media.ifEmpty { listOfNotNull(event.imageUrl?.let { EventMedia(MediaKind.PHOTO, it) }) }
            .take(MediaRules.MAX_ITEMS)
        return EventDraft(
            title = event.title, description = event.description, category = event.category, city = event.city,
            address = event.address, latitude = event.latitude, longitude = event.longitude,
            startsAt = event.startsAt, endsAt = event.endsAt, timeZone = event.timeZone, capacity = room.capacity,
            imageUrl = event.imageUrl, minAge = room.minAge, maxAge = room.maxAge, approvalRequired = room.approvalRequired,
            contactUrl = room.contactUrl, media = media.map { DraftMedia.Remote(it) },
            mediaBase = if (event.mediaLoaded) media.flatMap { listOfNotNull(it.url, it.poster) }.toSet() else null,
            price = room.price
        )
    }
}

/** «Повторити» (docs/organizers-1.5.md, 1.5): щотижневий клуб не набирає подію наново. */
object EventRepeat {
    /**
     * Чернетка з власної спільнотної події, минулої чи майбутньої: усі поля, фото й відео. Дата й час — на тиждень
     * пізніше, і ще на тиждень, поки не в майбутньому; у поясі події, тож перехід на зимовий час не зсуває годину. Медіа
     * копіюються в теку нової події з публікацією ([DraftMedia.Copied]); стара обкладинка без медіа (подія до 1.5) — теж.
     * Афіша (без [Event.gathering]) чи зіпсований рядок — null.
     */
    fun draft(event: Event, now: Instant): EventDraft? {
        val edit = EventEdit.draft(event) ?: return null
        val zone = runCatching { TimeZone.of(event.timeZone) }.getOrNull() ?: return null
        var start = event.startInstant ?: return null
        var end = event.endInstant ?: return null
        do {
            start = start.plus(1, DateTimeUnit.WEEK, zone)
            end = end.plus(1, DateTimeUnit.WEEK, zone)
        } while (start <= now)
        return edit.copy(
            startsAt = start.toString(), endsAt = end.toString(),
            // Обкладинка — з медіа: стара адреса з теки іншої події не пройшла б перевірку сервера. Файли нової події
            // копіюються з публікацією, а базу правки нова подія не має.
            imageUrl = null, media = edit.media?.map { DraftMedia.Copied((it as DraftMedia.Remote).media) }, mediaBase = null
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
     * Анонс поширює лише організатор власної звичайної спільнотної події, що ще попереду й не скасована. Усі інші діляться
     * з другом: творець «Шукаю компанію» (його збір — про чужу афішу), гість на чужій події, афіша. [me] — id акаунта, null — гість.
     */
    fun mode(event: Event, me: String?, now: Instant): ShareMode {
        val room = event.gathering
        // Скасовану чи минулу анонсувати нема куди: ділимось, як і «Покликати» ([canInvite] деталей), з другом.
        val live = !event.isCalledOff && !event.hasEnded(now)
        return if (me != null && room != null && room.companionOf == null && room.organizerId == me && live) ShareMode.PROMOTE else ShareMode.FRIEND
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
     * Вхід — {300} ₴, оплата на місці (чи «оплата онлайн») — лише з ціною, як у кабінеті (`threadsPost` у site/js/poriad.js)
     *
     * {blurb або перші 200 символів опису}
     *
     * Запис: poriad.app/e/{id}
     * ```
     * Час — у поясі події. Порожній опис — без абзацу.
     */
    fun text(event: Event): String = text(
        event.id, event.displayTitle, event.startsAt, event.timeZone, event.placeLabel, event.blurb, event.description,
        event.gathering?.price, event.gathering?.payOnline == true
    )

    /** Те саме з полів: щойно опублікована подія ([EventDraft]) ще не має картки. */
    fun text(
        id: String, title: String, startsAt: String, timeZone: String, place: String, blurb: String?, description: String, price: Int?,
        payOnline: Boolean = false
    ): String {
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
            listOfNotNull(
                title, listOfNotNull(date, place.takeIf { it.isNotBlank() }).joinToString(" · "),
                price?.let { "Вхід — " + EventRules.formatPrice(it) + " ₴, " + if (payOnline) "оплата онлайн" else "оплата на місці" }
            ).joinToString("\n"),
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
