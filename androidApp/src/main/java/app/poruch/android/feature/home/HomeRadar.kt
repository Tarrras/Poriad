package app.poruch.android.feature.home

import androidx.compose.foundation.clickable
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
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import app.poruch.android.R
import app.poruch.android.ui.*
import app.poruch.domain.ArtistHit
import app.poruch.domain.ArtistRadar
import app.poruch.domain.FollowKind
import app.poruch.domain.PopularArtist
import app.poruch.domain.RadarRules
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

/** Рядок «Ваших артистів»: є подія в місті — «сб 14.12 · назва»; нема — тур іншими містами; нема ніде — без анонсів. */
@Composable
private fun radarLine(row: ArtistRadar): String {
    row.next?.let { next -> date(next.startsAt, next.timeZone, WEEKDAY_DAY)?.let { return "$it · ${next.displayTitle}" } }
    if (row.elsewhere.isNotEmpty()) {
        val cities = row.elsewhere.joinToString(", ") { city -> date(city.startsAt, "Europe/Kyiv", DAY)?.let { "${city.city} $it" } ?: city.city }
        return stringResource(R.string.radar_elsewhere, cities)
    }
    return stringResource(R.string.radar_quiet)
}

/**
 * Радар артистів на головній (docs/artist-radar.md): «Ваші артисти»; без підписок на артистів секції нема. Хто їде в місто —
 * з датою, тап веде на подію; решта — тур чи «Поки нових анонсів нема», тап веде на артиста. До п'яти рядків, решта
 * розгортається тут же. Гість теж: стежить без входу.
 */
@Composable
internal fun RadarSection(state: HomeState, onIntent: (HomeIntent) -> Unit) {
    var picking by remember { mutableStateOf(false) }
    val rows = state.screen.radar
    if (rows.isEmpty()) return
    var all by remember { mutableStateOf(false) }
    val colors = Poruch.colors
    Column(Modifier.padding(horizontal = Spacing.page).padding(top = Spacing.xxl), verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
        SectionHeader(stringResource(R.string.radar_title), actionLabel = stringResource(R.string.radar_add), onAction = { picking = true })
        GroupedRows {
            (if (all) rows else rows.take(RadarRules.HOME_ROWS)).forEachIndexed { index, row ->
                if (index > 0) HairLine(Modifier.padding(start = Spacing.lg))
                Row(
                    Modifier.fillMaxWidth().semantics(mergeDescendants = true) { role = Role.Button }.clickable {
                        val next = row.next
                        if (next != null) onIntent(HomeIntent.OpenEvent(next.eventId, "radar"))
                        else onIntent(HomeIntent.OpenArtist(ArtistHit(row.artistId, row.name, row.kind, 0)))
                    }.padding(horizontal = Spacing.lg, vertical = Spacing.md),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.md)
                ) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(row.name, style = MaterialTheme.typography.titleSmall, color = colors.ink)
                        Text(radarLine(row), style = MaterialTheme.typography.bodySmall, color = if (row.next != null) colors.ink else colors.inkSecondary, maxLines = 2)
                    }
                    Icon(PoruchIcons.chevronRight, null, Modifier.size(16.dp), tint = colors.inkTertiary)
                }
            }
        }
        if (!all && rows.size > RadarRules.HOME_ROWS) {
            GhostButton(stringResource(R.string.radar_more, (rows.size - RadarRules.HOME_ROWS).toString()), { all = true }, Modifier.align(Alignment.CenterHorizontally))
        }
    }
    if (picking) RadarPickerSheet(koinInject()) { picking = false }
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
    var picked by remember { mutableStateOf(emptySet<String>()) }
    LaunchedEffect(Unit) { app.loadPopularArtists(false) }
    val close = { app.radarPickerClosed(artists?.size ?: 0, picked.size, "picker"); onDone() }
    PoruchSheet(close) { sheet ->
        Column(Modifier.padding(horizontal = Spacing.page).padding(bottom = Spacing.section), verticalArrangement = Arrangement.spacedBy(Spacing.lg)) {
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                Text(stringResource(R.string.radar_ask_title), style = PoruchType.brandTitle1, color = colors.ink, modifier = Modifier.semantics { heading() })
                Text(stringResource(R.string.radar_picker_hint), style = MaterialTheme.typography.bodyMedium, color = colors.inkSecondary)
            }
            PopularArtistChips(
                artists, { it in followed }, picked, dates = true,
                Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState())
            ) { id -> picked = if (id in picked) picked - id else picked + id }
            if (picked.isNotEmpty()) PrimaryButton(stringResource(R.string.radar_picker_follow, picked.size.toString()), {
                app.followArtists(artists.orEmpty().filter { it.artistId in picked }, "picker")
                sheet.close()
            }, Modifier.fillMaxWidth(), icon = PoruchIcons.bell)
        }
    }
}

/**
 * Хто виступає ([artists]) чипами: обрані — у [picked]; за ким уже стежать ([followed]) — позначені й тут не знімаються.
 * [dates] — найближча дата в місті; в онбордингу список по країні, і дата з іншого міста збивала б. Null — ще їде.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun PopularArtistChips(
    artists: List<PopularArtist>?, followed: (String) -> Boolean, picked: Set<String>, dates: Boolean,
    modifier: Modifier = Modifier, onToggle: (String) -> Unit
) {
    val colors = Poruch.colors
    when {
        artists == null -> Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
            CircularProgressIndicator(Modifier.size(24.dp), color = colors.ink, strokeWidth = 2.dp)
        }
        artists.isEmpty() -> Text(stringResource(R.string.radar_picker_empty), style = MaterialTheme.typography.bodyLarge, color = colors.inkSecondary)
        else -> FlowRow(modifier, horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            artists.forEach { artist ->
                val already = followed(artist.artistId)
                val on = already || artist.artistId in picked
                val first = if (dates) artist.firstAt?.let { date(it, "Europe/Kyiv", DAY) } else null
                PoruchChip(first?.let { "${artist.name} · $it" } ?: artist.name, on, {
                    if (!already) onToggle(artist.artistId)
                }, icon = if (on) PoruchIcons.check else null, maxLines = 2)
            }
        }
    }
}
