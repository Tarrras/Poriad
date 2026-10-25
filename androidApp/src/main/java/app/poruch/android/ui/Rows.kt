package app.poruch.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.poruch.android.R
import app.poruch.domain.ArtistHit
import app.poruch.domain.DiscoveryRules
import app.poruch.domain.DistrictHit
import app.poruch.domain.Place

/** Рядок артиста в пошуку: піктограма людини, ім'я й скільки подій попереду. */
@Composable
fun ArtistRow(artist: ArtistHit, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val colors = Poruch.colors
    val subtitle = listOfNotNull(
        artistKindLabel(artist.kind),
        pluralStringResource(R.plurals.place_upcoming, artist.upcoming, artist.upcoming)
    )
        .joinToString(" · ")
    Row(
        modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = true) {}
            .pressable(onClick = onClick)
            .padding(horizontal = Spacing.lg, vertical = Spacing.md),
        horizontalArrangement = Arrangement.spacedBy(Spacing.md),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            Modifier
                .size(40.dp)
                .background(colors.surfaceMuted, Radius.xs),
            contentAlignment = Alignment.Center
        ) {
            Icon(PoruchIcons.person, null, Modifier.size(20.dp), tint = colors.ink)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                artist.name,
                style = PoruchType.brandTitle3,
                color = colors.ink,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = colors.inkSecondary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

/** Рядок закладу в пошуку: піктограма місця, назва, адреса й скільки подій попереду. */
@Composable
fun PlaceRow(
    place: Place,
    modifier: Modifier = Modifier,
    withCity: Boolean = false,
    onClick: () -> Unit
) {
    val colors = Poruch.colors
    val address = if (withCity && place.city.isNotBlank() && !place.address.contains(place.city)) {
        listOf(place.city, place.address).filter { it.isNotBlank() }.joinToString(", ")
    } else place.address
    val subtitle = listOf(
        address,
        pluralStringResource(R.plurals.place_upcoming, place.upcoming, place.upcoming)
    )
        .filter { it.isNotBlank() }.joinToString(" · ")
    Row(
        modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = true) {}
            .pressable(onClick = onClick)
            .padding(horizontal = Spacing.lg, vertical = Spacing.md),
        horizontalArrangement = Arrangement.spacedBy(Spacing.md),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            Modifier
                .size(40.dp)
                .background(colors.surfaceMuted, Radius.xs),
            contentAlignment = Alignment.Center
        ) {
            Icon(PoruchIcons.pin, null, Modifier.size(20.dp), tint = colors.ink)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                place.name, style = PoruchType.brandTitle3, color = colors.ink,
                maxLines = 1, overflow = TextOverflow.Ellipsis
            )
            Text(
                subtitle, style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary,
                maxLines = 2, overflow = TextOverflow.Ellipsis
            )
        }
    }
}

/**
 * Рядок району в пошуку: гліф межі, назва й скільки в ньому подій міста — те число, що покаже мапа. Порожній район теж
 * рядок: «Поки без подій» чесно каже, що район є, а подій нема. Після нещодавнього перейменування — «раніше …».
 */
@Composable
fun DistrictRow(hit: DistrictHit, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val colors = Poruch.colors
    val subtitle = listOfNotNull(
        if (hit.upcoming > 0) pluralStringResource(R.plurals.place_upcoming, hit.upcoming, hit.upcoming)
        else stringResource(R.string.district_no_events),
        hit.district.formerShort?.let { stringResource(R.string.district_former, it) },
        // Місцевість — коло навколо точки OSM: кажемо, скільки охоплено, а не «в Аркадії».
        hit.district.radiusKm?.let { stringResource(R.string.locality_radius, it) }
    ).joinToString(" · ")
    Row(
        modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = true) {}
            .pressable(onClick = onClick)
            .padding(horizontal = Spacing.lg, vertical = Spacing.md),
        horizontalArrangement = Arrangement.spacedBy(Spacing.md),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            Modifier
                .size(40.dp)
                .background(colors.surfaceMuted, Radius.xs),
            contentAlignment = Alignment.Center
        ) {
            Icon(PoruchIcons.district, null, Modifier.size(20.dp), tint = colors.ink)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                hit.district.name, style = PoruchType.brandTitle3, color = colors.ink,
                maxLines = 1, overflow = TextOverflow.Ellipsis
            )
            // Два рядки: на великому шрифті «раніше Малиновський» — саме те, за чим людина шукала, — не обрізається.
            Text(
                subtitle, style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary,
                maxLines = 2, overflow = TextOverflow.Ellipsis
            )
        }
    }
}

/** Рядок групового списку: гліф, назва, підпис, справа значення й шеврон. Кілька рядків збирає [GroupedRows]. */
@Composable
fun LinkRow(
    icon: ImageVector,
    title: String,
    subtitle: String? = null,
    onClick: () -> Unit,
    value: String? = null,
    /** Що нового за рядком («3 нові»): помітніше за [value]. */
    badge: String? = null
) {
    val colors = Poruch.colors
    Row(
        Modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = true) { role = Role.Button }
            .clickable(onClick = onClick)
            .padding(Spacing.lg),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        Box(
            Modifier
                .size(40.dp)
                .background(colors.surfaceMuted, Radius.xs),
            contentAlignment = Alignment.Center
        ) {
            Icon(icon, null, Modifier.size(20.dp), tint = colors.ink)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = MaterialTheme.typography.titleSmall, color = colors.ink)
            if (subtitle != null) Text(
                subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = colors.inkSecondary
            )
            // Під підписом, як у списку підписок: праворуч поруч із числом він стискав підпис у три рядки.
            if (badge != null) Box(Modifier.padding(top = Spacing.xs)) { StatusBadge(badge, BadgeTone.Accent) }
        }
        if (value != null) Text(
            value,
            style = MaterialTheme.typography.titleLarge,
            color = colors.ink
        )
        Icon(PoruchIcons.chevronRight, null, Modifier.size(18.dp), tint = colors.inkTertiary)
    }
}

/** Підпис над [GroupedRows] капітеллю: «Події · 7», «Місця». Праворуч — необов'язкова дія. */
@Composable
fun GroupLabel(
    text: String,
    modifier: Modifier = Modifier,
    actionLabel: String? = null,
    onAction: (() -> Unit)? = null
) {
    val colors = Poruch.colors
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(
            text.uppercase(),
            style = MaterialTheme.typography.labelSmall,
            color = colors.inkTertiary,
            modifier = Modifier
                .weight(1f)
                .semantics { heading() }
        )
        if (actionLabel != null && onAction != null) Text(
            actionLabel, style = MaterialTheme.typography.labelMedium, color = colors.ink,
            modifier = Modifier
                .clip(Radius.pill)
                .clickable(onClick = onAction)
                .padding(horizontal = Spacing.sm, vertical = Spacing.xs)
        )
    }
}

/** Секція «Місця» у видачі пошуку: заклади з тим самим словом. Тап — мапа на закладі. */
@Composable
fun PlacesGroup(
    places: List<Place>,
    withCity: Boolean,
    modifier: Modifier = Modifier,
    onOpen: (Place) -> Unit
) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        GroupLabel(stringResource(R.string.search_places_group))
        GroupedRows {
            places.forEachIndexed { position, place ->
                if (position > 0) HairLine(Modifier.padding(start = Spacing.lg + 40.dp + Spacing.md))
                PlaceRow(place, withCity = withCity) { onOpen(place) }
            }
        }
    }
}

/** Секція «Райони» над «Місцями»: райони міста за тим самим словом. Тап — мапа в районі. */
@Composable
fun DistrictsGroup(
    districts: List<DistrictHit>,
    modifier: Modifier = Modifier,
    /** «Райони» чи «Місцевості». */
    title: String = stringResource(R.string.search_districts_group),
    onOpen: (DistrictHit) -> Unit
) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        GroupLabel(title)
        GroupedRows {
            districts.forEachIndexed { position, hit ->
                if (position > 0) HairLine(Modifier.padding(start = Spacing.lg + 40.dp + Spacing.md))
                DistrictRow(hit) { onOpen(hit) }
            }
        }
    }
}

/** Секція «Артисти» у видачі пошуку під «Місцями». Тап — екран артиста. */
@Composable
fun ArtistsGroup(
    artists: List<ArtistHit>,
    modifier: Modifier = Modifier,
    onOpen: (ArtistHit) -> Unit
) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        GroupLabel(stringResource(R.string.search_artists_group))
        GroupedRows {
            artists.take(DiscoveryRules.ARTISTS_LIMIT).forEachIndexed { position, artist ->
                if (position > 0) HairLine(Modifier.padding(start = Spacing.lg + 40.dp + Spacing.md))
                ArtistRow(artist) { onOpen(artist) }
            }
        }
    }
}

/** Біла картка з рядками; лінія між ними йде від тексту, а не від краю. */
@Composable
fun GroupedRows(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) =
    Column(
        modifier
            .fillMaxWidth()
            .cardSurface(), content = content
    )
