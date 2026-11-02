package app.poruch.android.feature.editor

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewModelScope
import app.poruch.android.R
import app.poruch.android.mvi.MviViewModel
import app.poruch.android.ui.*
import app.poruch.domain.EventMedia
import app.poruch.domain.MediaKind
import app.poruch.domain.ShareMode
import app.poruch.domain.TitleRules
import app.poruch.android.feature.known
import app.poruch.shared.PoruchApp
import app.poruch.shared.PublishAction
import app.poruch.shared.PublishedEvent
import com.airbnb.lottie.compose.LottieAnimation
import com.airbnb.lottie.compose.LottieCompositionSpec
import com.airbnb.lottie.compose.animateLottieCompositionAsState
import com.airbnb.lottie.compose.rememberLottieComposition
import kotlinx.coroutines.launch

// «Подію створено» (docs/organizers-1.5.md, 1.6): після публікації — не одразу деталі, а дії з посиланням.

data class PublishedState(
    /** Зі спільного стану ([app.poruch.shared.AppState.published]); null — екран більше не потрібен. */
    val published: PublishedEvent? = null,
    /** «Поділитися з другом» чекає особисте посилання. */
    val sharing: Boolean = false
)

sealed interface PublishedIntent {
    data object Share : PublishedIntent
    data object Copy : PublishedIntent
    data object Calendar : PublishedIntent
    /** «Готово» чи системне «назад». */
    data object Done : PublishedIntent
}

sealed interface PublishedEffect {
    /** «Поширити анонс»: пост для Threads з фото й відео події, якщо їх уже видно. */
    data class Promote(val media: List<EventMedia>, val post: String) : PublishedEffect
    /** «Поділитися з другом»: особисте посилання `?by=`. */
    data class Friend(val link: String) : PublishedEffect
    data class Copy(val link: String) : PublishedEffect
    data class Calendar(val event: PublishedEvent) : PublishedEffect
    data class OpenDetail(val id: String) : PublishedEffect
    /** Стану нема (процес відновився з цим екраном): назад. */
    data object Close : PublishedEffect
}

class PublishedViewModel(private val app: PoruchApp) : MviViewModel<PublishedState, PublishedIntent, PublishedEffect>(PublishedState()) {
    private var closed = false

    init {
        observe(app) { shared ->
            if (shared.published == null && !closed) { closed = true; send(PublishedEffect.Close) }
            copy(published = shared.published ?: published)
        }
    }

    override fun onIntent(intent: PublishedIntent) {
        val published = state.value.published ?: return
        when (intent) {
            PublishedIntent.Share -> if (!state.value.sharing) {
                app.publishDone(PublishAction.SHARE)
                viewModelScope.launch {
                    reduce { copy(sharing = true) }
                    val effect = try {
                        if (published.shareMode == ShareMode.PROMOTE) PublishedEffect.Promote(media(published.id), published.post)
                        // Особисте посилання — від сервера; без мережі — звичайне, а не падіння.
                        else PublishedEffect.Friend(runCatching { app.inviteLink(published.id) }.getOrDefault(published.link))
                    } finally { reduce { copy(sharing = false) } }
                    send(effect)
                }
            }
            PublishedIntent.Copy -> { app.publishDone(PublishAction.COPY); send(PublishedEffect.Copy(published.link)) }
            PublishedIntent.Calendar -> { app.publishDone(PublishAction.CALENDAR); send(PublishedEffect.Calendar(published)) }
            PublishedIntent.Done -> {
                closed = true
                app.publishDone(PublishAction.DONE)
                send(PublishedEffect.OpenDetail(published.id))
            }
        }
    }

    /**
     * Фото й відео щойно опублікованої — лише з повних деталей ([known]); ще не приїхали — дочитуємо. Не вдалось — пост з
     * текстом без файлів (текст однаково в буфері), а збій каже банер.
     */
    private suspend fun media(id: String): List<EventMedia> {
        val event = app.known(id) ?: run { app.reloadEvent(id); app.known(id) }
        return event?.let { it.media.ifEmpty { listOfNotNull(it.imageUrl?.let { url -> EventMedia(MediaKind.PHOTO, url) }) } }.orEmpty()
    }
}

@Composable
fun PublishedScreen(state: PublishedState, onIntent: (PublishedIntent) -> Unit) {
    val colors = Poruch.colors
    BackHandler { onIntent(PublishedIntent.Done) }
    val published = state.published ?: return
    Column(
        Modifier.fillMaxSize().background(colors.canvas).statusBarsPadding().navigationBarsPadding()
            .verticalScroll(rememberScrollState()).padding(Spacing.page),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        Spacer(Modifier.height(Spacing.section))
        // Раз; без анімацій — одразу останній кадр (штамп уже стоїть).
        val composition by rememberLottieComposition(LottieCompositionSpec.RawRes(R.raw.published))
        val reduced = Poruch.reducedMotion
        val progress by animateLottieCompositionAsState(composition, isPlaying = !reduced)
        LottieAnimation(composition, { if (reduced) 1f else progress }, Modifier.size(220.dp))
        Text(
            stringResource(R.string.published_title), style = PoruchType.brandTitle1, color = colors.ink, textAlign = TextAlign.Center,
            modifier = Modifier.semantics { heading() }
        )
        Text(TitleRules.display(published.title), style = MaterialTheme.typography.bodyLarge, color = colors.inkSecondary, textAlign = TextAlign.Center)
        Spacer(Modifier.height(Spacing.md))
        PrimaryButton(
            stringResource(if (published.shareMode == ShareMode.PROMOTE) R.string.share_promote else R.string.share_friend),
            { onIntent(PublishedIntent.Share) }, Modifier.fillMaxWidth(), icon = PoruchIcons.share, loading = state.sharing
        )
        SecondaryButton(stringResource(R.string.published_copy_link), { onIntent(PublishedIntent.Copy) }, Modifier.fillMaxWidth(), icon = PoruchIcons.link)
        SecondaryButton(stringResource(R.string.published_calendar), { onIntent(PublishedIntent.Calendar) }, Modifier.fillMaxWidth(), icon = PoruchIcons.calendar)
        GhostButton(stringResource(R.string.published_done), { onIntent(PublishedIntent.Done) }, tone = colors.ink)
    }
}

@Preview(heightDp = 760)
@Composable
private fun PublishedPreview() = PoruchTheme(dark = false) {
    PublishedScreen(PublishedState(PREVIEW_PUBLISHED)) {}
}

@Preview(heightDp = 760)
@Composable
private fun PublishedFriendDarkPreview() = PoruchTheme(dark = true) {
    PublishedScreen(PublishedState(PREVIEW_PUBLISHED.copy(shareMode = ShareMode.FRIEND), sharing = true)) {}
}

private val PREVIEW_PUBLISHED = PublishedEvent(
    id = "preview", link = "https://poriad.app/e/preview", post = "", shareMode = ShareMode.PROMOTE,
    title = "Вечір настільних ігор у «Протісто»", startMillis = 0, endMillis = 0, timeZone = "Europe/Kyiv", location = "Київ"
)
