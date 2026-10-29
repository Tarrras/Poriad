package app.poruch.android.feature.home

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import app.poruch.android.R
import app.poruch.android.ui.*
import app.poruch.domain.ArtistRadar
import app.poruch.domain.DiscoveryRules
import app.poruch.domain.FollowKind
import app.poruch.domain.PopularArtist
import app.poruch.shared.PoruchApp
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import org.koin.compose.koinInject

private val UKRAINIAN = Locale.forLanguageTag("uk")

/** Форматери — раз на процес, а не на кожне перескладання рядка. */
private val DAY = DateTimeFormatter.ofPattern("d.MM", UKRAINIAN)
private val WEEKDAY_DAY = DateTimeFormatter.ofPattern("EE d.MM", UKRAINIAN)

private fun date(iso: String, zone: String, format: DateTimeFormatter): String? = runCatching {
    OffsetDateTime.parse(iso).atZoneSameInstant(ZoneId.of(zone)).format(format)
}.getOrNull()

/**
 * Підпис артиста на екрані «Ви стежите»: є подія в місті — «сб 14.12 · назва»; нема — тур іншими містами; нема ніде — без
 * анонсів. Дати в місті на головній — рядками «Ваше» (`PersonalSection`), решта видно там.
 */
@Composable
internal fun radarLine(row: ArtistRadar): String {
    row.next?.let { next -> date(next.startsAt, next.timeZone, WEEKDAY_DAY)?.let { return "$it · ${next.displayTitle}" } }
    if (row.elsewhere.isNotEmpty()) {
        val cities = row.elsewhere.joinToString(", ") { city -> date(city.startsAt, "Europe/Kyiv", DAY)?.let { "${city.city} $it" } ?: city.city }
        return stringResource(R.string.radar_elsewhere, cities)
    }
    return stringResource(R.string.radar_quiet)
}

/**
 * «За ким стежити?» (docs/artist-radar.md): хто їде в місто людини, найбільше вечорів першими. Вибір кількох, «Стежити за 3».
 * Хто вже в підписках — позначений і тут не знімається.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun RadarPickerSheet(app: PoruchApp, onDone: () -> Unit) {
    val colors = Poruch.colors
    // Лише артисти й підписки на них: шторці нема діла до чатів і мапи.
    val artists by remember { app.state.map { it.popularArtists }.distinctUntilChanged() }.collectAsState(app.state.value.popularArtists)
    val followed by remember {
        app.state.map { s -> s.library.follows.filter { it.kind == FollowKind.ARTIST }.map { it.targetId }.toSet() }.distinctUntilChanged()
    }.collectAsState(emptySet())
    val matches by remember { app.state.map { it.artistMatches }.distinctUntilChanged() }.collectAsState(app.state.value.artistMatches)
    var query by remember { mutableStateOf("") }
    var picked by remember { mutableStateOf(emptyMap<String, PopularArtist>()) }
    LaunchedEffect(Unit) { app.loadPopularArtists(false) }
    val close = { app.radarPickerClosed(artists?.size ?: 0, picked.size, "picker"); onDone() }
    PoruchSheet(close) { sheet ->
        Column(Modifier.padding(horizontal = Spacing.page).padding(bottom = Spacing.section), verticalArrangement = Arrangement.spacedBy(Spacing.lg)) {
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                Text(stringResource(R.string.radar_ask_title), style = PoruchType.brandTitle1, color = colors.ink, modifier = Modifier.semantics { heading() })
                Text(stringResource(R.string.radar_picker_hint), style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary)
            }
            PoruchSearchField(query, { query = it; app.searchArtists(it) }, stringResource(R.string.radar_search), Modifier.fillMaxWidth())
            PopularArtistChips(
                artists, matches, query, { it in followed }, picked, dates = true,
                Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState())
            ) { artist -> picked = picked.toggle(artist) }
            if (picked.isNotEmpty()) PrimaryButton(stringResource(R.string.radar_picker_follow, picked.size.toString()), {
                app.followArtists(picked.values.toList(), "picker")
                sheet.close()
            }, Modifier.fillMaxWidth(), icon = PoruchIcons.bell)
        }
    }
}

/** Обрати чи зняти [artist] у шторці й на кроці онбордингу. */
internal fun Map<String, PopularArtist>.toggle(artist: PopularArtist) =
    if (artist.artistId in this) this - artist.artistId else this + (artist.artistId to artist)

/**
 * Чипи артистів: без запиту ([query] коротший за два символи) — хто виступає ([artists]), із запитом — збіги по всій
 * країні ([matches]). Обрані — у [picked]; за ким уже стежать ([followed]) — позначені й тут не знімаються. [dates] —
 * найближча дата в місті; в онбордингу список по країні, і дата з іншого міста збивала б. Null — ще їде.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun PopularArtistChips(
    artists: List<PopularArtist>?, matches: List<PopularArtist>?, query: String, followed: (String) -> Boolean,
    picked: Map<String, PopularArtist>, dates: Boolean, modifier: Modifier = Modifier, onToggle: (PopularArtist) -> Unit
) {
    val colors = Poruch.colors
    val searching = query.trim().length >= DiscoveryRules.MIN_ARTIST_QUERY
    // Без запиту обрані пошуком стоять першими: інакше вони зникали б, лишаючись у «Стежити за N».
    val shown = if (searching) matches else artists?.let { popular ->
        val ids = popular.mapTo(HashSet()) { it.artistId }
        picked.values.filter { it.artistId !in ids }.sortedBy { it.name } + popular
    }
    when {
        shown == null -> Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
            CircularProgressIndicator(Modifier.size(24.dp), color = colors.ink, strokeWidth = 2.dp)
        }
        shown.isEmpty() -> Text(
            if (searching) stringResource(R.string.radar_search_empty, query.trim()) else stringResource(R.string.radar_picker_empty),
            style = MaterialTheme.typography.bodyLarge, color = colors.inkSecondary
        )
        else -> FlowRow(modifier, horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            shown.forEach { artist ->
                val already = followed(artist.artistId)
                val on = already || artist.artistId in picked
                val first = if (dates) artist.firstAt?.let { date(it, "Europe/Kyiv", DAY) } else null
                PoruchChip(first?.let { "${artist.name} · $it" } ?: artist.name, on, { onToggle(artist) },
                    icon = if (on) PoruchIcons.check else null, maxLines = 2, enabled = !already)
            }
        }
    }
}
