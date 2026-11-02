package app.poruch.android.feature

import app.poruch.domain.Event
import app.poruch.shared.PoruchApp

/**
 * Подія з повними фото й відео ([Event.mediaLoaded]). Картки стрічки й «Моїх подій» медіа не несуть, тож «Повторити» й
 * «Пост для Threads» з картки вийшли б лише з обкладинкою (а з відео — з постером як фото). Тоді перечитуємо деталі
 * (`event_details`). Не доїхали — null: дія не йде мовчки без медіа, а збій уже каже банер спільного шару.
 * Те саме, що `withMedia` на iOS.
 */
internal suspend fun PoruchApp.withMedia(event: Event): Event? {
    if (event.mediaLoaded) return event
    known(event.id)?.let { return it }
    reloadEvent(event.id)
    return state.value.detail.takeIf { it.failure == null && !it.loading }?.event?.takeIf { it.id == event.id && it.mediaLoaded }
}

/** Повна подія [id], якщо застосунок її вже має: відкриті деталі чи «Мої події». */
internal fun PoruchApp.known(id: String): Event? = state.value.let { shared ->
    (listOfNotNull(shared.detail.event) + shared.library.myEvents).firstOrNull { it.id == id && it.mediaLoaded }
}
