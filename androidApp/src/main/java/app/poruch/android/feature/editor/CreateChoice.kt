package app.poruch.android.feature.editor

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import app.poruch.android.R
import app.poruch.android.ui.CreateEventCard
import app.poruch.android.ui.Poruch
import app.poruch.android.ui.PoruchIcons
import app.poruch.android.ui.PoruchSheet
import app.poruch.android.ui.PoruchTheme
import app.poruch.android.ui.PoruchType
import app.poruch.android.ui.Spacing
import app.poruch.android.ui.Ticket
import app.poruch.android.ui.categoryStub
import app.poruch.domain.EventCategory

/**
 * «+» питає одне (docs/creation-platform-plan-2026-11.md, етап 2): покликати компанію на подію з афіші чи зібрати свою
 * зустріч. Два квитки: надрукований, з корінцем жанру — афіша; порожній з олівцем — свою друкуєш сам. [onChoice]: true —
 * своя зустріч, false — афіша, null — шторку закрили.
 */
@Composable
fun CreateChoiceSheet(onChoice: (Boolean?) -> Unit) = PoruchSheet({ onChoice(null) }) { sheet ->
    CreateChoice { own -> sheet.close { onChoice(own) } }
}

@Composable
private fun CreateChoice(onChoice: (Boolean) -> Unit) {
    val colors = Poruch.colors
    Column(
        Modifier.padding(horizontal = Spacing.page).padding(bottom = Spacing.section),
        verticalArrangement = Arrangement.spacedBy(Spacing.md)
    ) {
        Text(
            stringResource(R.string.create_choice_title), style = PoruchType.brandTitle2, color = colors.ink,
            modifier = Modifier.padding(bottom = Spacing.xs).semantics { heading() }
        )
        // Своя зустріч — першою: створення під «+» (принцип 2), а на афішу йдуть з самої афіші.
        CreateEventCard(
            stringResource(R.string.create_choice_own), stringResource(R.string.create_choice_own_hint), { onChoice(true) }
        )
        Ticket(
            categoryStub(EventCategory.MUSIC),
            stub = { Icon(PoruchIcons.ticket, null, Modifier.size(22.dp), tint = Color.White) },
            modifier = Modifier.fillMaxWidth(), stubLength = 64.dp, surface = colors.surfaceMuted, onClick = { onChoice(false) }
        ) {
            Column(
                Modifier.heightIn(min = 72.dp).padding(horizontal = Spacing.lg, vertical = Spacing.md),
                verticalArrangement = Arrangement.spacedBy(2.dp, Alignment.CenterVertically)
            ) {
                Text(stringResource(R.string.create_choice_afisha), style = PoruchType.brandTitle3, color = colors.ink)
                Text(stringResource(R.string.create_choice_afisha_hint), style = MaterialTheme.typography.bodySmall, color = colors.inkSecondary)
            }
        }
    }
}

@Preview(widthDp = 360)
@Composable
private fun CreateChoicePreview() = PoruchTheme(dark = false) { CreateChoice {} }
