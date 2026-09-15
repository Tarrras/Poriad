package app.poruch.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SheetState
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/**
 * Усі питання ставимо шторкою знизу, а не діалогом Material: вона на нашому папері, під великим
 * пальцем і прибирається тим самим жестом, що й фільтри. [content] отримує [PoruchSheetScope]:
 * відповідайте через `close { … }`, щоб шторка виїхала, а не блимнула.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PoruchSheet(
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.(PoruchSheetScope) -> Unit
) {
    val colors = Poruch.colors
    // Кожна шторка несе одне рішення, тому без напіввідкритого стану: він сховав би кнопку.
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val scope = rememberCoroutineScope()
    val reducedMotion = Poruch.reducedMotion
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        modifier = modifier,
        sheetState = state,
        shape = Radius.sheet,
        containerColor = colors.surface,
        contentColor = colors.ink,
        // Теплий чорний, не сіра вуаль: нейтральний scrim на теплому папері виглядає як бруд.
        scrimColor = (if (colors.dark) colors.canvas else colors.ink).copy(alpha = if (colors.dark) 0.62f else 0.32f),
        dragHandle = { SheetHandle() }
    ) {
        content(PoruchSheetScope(state, scope, reducedMotion, onDismiss))
    }
}

/** Тонка риска замість пігулки Material: шторка — папір, ручка — згин. */
@Composable
private fun SheetHandle() {
    Box(
        Modifier.fillMaxWidth().padding(top = Spacing.md, bottom = Spacing.sm),
        contentAlignment = Alignment.Center
    ) {
        Box(Modifier.width(32.dp).height(4.dp).background(Poruch.colors.hairline, Radius.pill))
    }
}

/** Дає вмісту шторки спосіб прибрати її перед дією. */
@OptIn(ExperimentalMaterial3Api::class)
class PoruchSheetScope internal constructor(
    private val state: SheetState,
    private val scope: CoroutineScope,
    private val reducedMotion: Boolean,
    private val onDismiss: () -> Unit
) {
    /** Виїжджає, потім повідомляє про закриття і виконує [then]. Без анімацій не чекає. */
    fun close(then: () -> Unit = {}) {
        if (reducedMotion) {
            onDismiss(); then(); return
        }
        scope.launch { state.hide() }.invokeOnCompletion {
            if (!state.isVisible) { onDismiss(); then() }
        }
    }
}

/** Питання з двома відповідями. Деструктивна — кнопка, вихід — тихіша під нею. */
@Composable
fun PoruchConfirmSheet(
    title: String,
    message: String,
    confirmLabel: String,
    dismissLabel: String,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
    tone: Color? = null
) {
    val colors = Poruch.colors
    PoruchSheet(onDismiss) { sheet ->
        Column(
            Modifier.padding(horizontal = Spacing.page).padding(bottom = Spacing.section),
            verticalArrangement = Arrangement.spacedBy(Spacing.md)
        ) {
            Text(title, style = MaterialTheme.typography.titleLarge, color = colors.ink)
            Text(
                message, style = MaterialTheme.typography.bodyLarge, color = colors.inkSecondary,
                modifier = Modifier.padding(bottom = Spacing.sm)
            )
            PrimaryButton(confirmLabel, { sheet.close(onConfirm) }, Modifier.fillMaxWidth(), tone = tone)
            SecondaryButton(dismissLabel, { sheet.close() }, Modifier.fillMaxWidth())
        }
    }
}
