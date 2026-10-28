package app.poruch.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.foundation.layout.offset
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.poruch.android.R
import app.poruch.domain.Event

/**
 * Порожній квиток «Організувати подію»: свою зустріч друкуєш сам. Корінець чорнильний — це головна дія екрана; контур
 * пунктиром. Головна одиниця застосунку — зустріч від людини, тож дорога до неї видна одразу. Гостя тап веде до входу.
 */
@Composable
fun CreateEventCard(
    title: String,
    subtitle: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    /** Олівець — «друкуєш сам»; інший гліф — та сама порожня форма для іншої першої дії («Знайти подію поруч»). */
    icon: ImageVector = PoruchIcons.edit
) {
    val colors = Poruch.colors
    Ticket(
        colors.brand,
        // Олівець, а не «+»: плюс уже є на кнопці створення біля таббара, а тут квиток заповнюють.
        stub = { Icon(icon, null, Modifier.size(22.dp), tint = colors.onBrand) },
        modifier = modifier.fillMaxWidth(),
        stubLength = 64.dp, outline = colors.inkTertiary.copy(alpha = 0.7f), onClick = onClick
    ) {
        Column(
            Modifier.heightIn(min = 72.dp).padding(horizontal = Spacing.lg, vertical = Spacing.md),
            verticalArrangement = Arrangement.spacedBy(2.dp, Alignment.CenterVertically)
        ) {
            Text(title, style = PoruchType.brandTitle3, color = colors.ink)
            Text(subtitle, style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary)
        }
    }
}

/**
 * Великий квиток-афіша: обкладинка зверху, назва й опис на поверхні, час на корінці; без фото — друкована сторона з назвою
 * великим кеглем. На головній їх кілька, гортаються.
 */
@Composable
fun EventHeroCard(
    event: Event, modifier: Modifier = Modifier, eyebrow: String? = null, height: Dp = 360.dp,
    saved: Boolean = false, onSave: (() -> Unit)? = null, onClick: () -> Unit
) {
    val colors = Poruch.colors
    // Штамп — лише стан квитка. Чому квиток тут («Для вас», «Від людей») — тихим рядком під описом.
    val stamp: Triple<String, BadgeTone, ImageVector?>? = eventState(event)?.let { Triple(it.first, it.second, null) }
    val reason: Pair<String, ImageVector>? = eyebrow?.let { it to PoruchIcons.sparkle }
        ?: if (event.gathering != null) stringResource(R.string.from_people) to PoruchIcons.social else null
    Ticket(
        ticketStub(event),
        stub = {
            Column(Modifier.fillMaxHeight(), horizontalAlignment = Alignment.CenterHorizontally) {
                if (onSave != null) SaveButton(saved, onSave, Modifier.padding(top = Spacing.md))
                Spacer(Modifier.weight(1f))
                StubTime(event, Modifier.padding(bottom = Spacing.xl))
            }
        },
        modifier = modifier.fillMaxWidth()
            .ticketSemantics(ticketA11yLabel(event, listOfNotNull(stamp?.first, reason?.first).joinToString(", ")), onClick, saved, onSave),
        radius = Corner.lg, onClick = onClick
    ) {
        val printed = event.imageUrl == null
        // Висота — найменша, а не стала: з великим шрифтом назва, місце й підпис джерела не обрізаються.
        Column(Modifier.heightIn(min = height)) {
            // Без фото обкладинки нема: квиток друкований — штамп і назва великим кеглем на самій поверхні.
            if (!printed) Box(Modifier.fillMaxWidth().height(height * 0.54f).clipToBounds()) {
                EventArt(event, Modifier.fillMaxSize(), glyph = 160.dp)
                stamp?.let { (text, tone, icon) -> TicketStamp(text, tone, icon, onFill = true, modifier = Modifier.padding(Spacing.md)) }
            } else stamp?.let { (text, tone, icon) ->
                TicketStamp(text, tone, icon, modifier = Modifier.padding(start = Spacing.lg, end = Spacing.lg, top = Spacing.lg))
            }
            Column(Modifier.padding(Spacing.lg), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                Text(
                    event.cardTitle, style = if (printed) PoruchType.brandDisplay else PoruchType.brandTitle1, color = colors.ink,
                    maxLines = if (printed) 5 else 2, overflow = TextOverflow.Ellipsis
                )
                HostLine(event)
                EventDescriptor(event)
                reason?.let { (text, icon) -> ReasonLine(text, icon) }
                artistsLine(event)?.let { MetaLine(PoruchIcons.person, it) }
                // Афіша підписана джерелом скрізь, і в стосі «Ваш тиждень» теж: так обіцяють Умови, розділ 7.
                event.listing?.let {
                    Text(
                        stringResource(R.string.listing_badge, it.sellerNames), style = MaterialTheme.typography.labelSmall,
                        color = colors.inkTertiary, maxLines = 1, overflow = TextOverflow.Ellipsis
                    )
                }
            }
        }
    }
}

/**
 * Афіша на всю обкладинку; без фото — насичений градієнт категорії з її великим прозорим гліфом.
 * Одна на hero й постер, щоб подія без фото не блідла серед подій із ним. [glyph] — розмір прозорого гліфа,
 * [glyphDrop] — наскільки його опустити (на деталях верх зайнятий смугою статусу й кнопками).
 */
@Composable
fun EventArt(
    event: Event,
    modifier: Modifier = Modifier,
    glyph: Dp = 220.dp,
    glyphDrop: Dp = 0.dp
) {
    if (event.imageUrl == null) Box(modifier.background(categoryHeroGradient(event.category))) {
        Icon(
            categoryIcon(event.category), null,
            Modifier
                .align(Alignment.TopEnd)
                .offset(x = glyph * 0.25f, y = glyphDrop - glyph * 0.04f)
                .size(glyph),
            tint = Color.White.copy(alpha = 0.18f)
        )
    } else EventImage(event, modifier, glyphSize = 72.dp)
}
