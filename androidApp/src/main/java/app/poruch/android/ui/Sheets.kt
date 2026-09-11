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
 * The app asks every question from the bottom edge.
 *
 * A Material dialog lands in the middle of the screen on a surface the design system never
 * declared, with its own radius, its own buttons and its own idea of where the important answer
 * goes. A sheet arrives on the app's own paper, within reach of the thumb that opened it, and it
 * is the same object the filters already are — so one downward drag puts any of them away.
 *
 * [content] receives a [PoruchSheetScope]: answer through `close { … }` rather than by dropping
 * the state yourself, and the sheet slides out instead of blinking away mid-animation.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PoruchSheet(
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.(PoruchSheetScope) -> Unit
) {
    val colors = Poruch.colors
    // Every sheet here carries one decision, so none of them has a half-open state to rest in:
    // a half-open sheet would hide its own confirming button below the fold.
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
        // A warm black, never a grey veil: over warm paper a neutral scrim reads as dirt on the
        // screen rather than as the room going dark. Both tokens named here are that same warm
        // black — `ink` is it on paper, and in dark mode the ink has gone pale, so the ground is.
        scrimColor = (if (colors.dark) colors.canvas else colors.ink).copy(alpha = if (colors.dark) 0.62f else 0.32f),
        dragHandle = { SheetHandle() }
    ) {
        content(PoruchSheetScope(state, scope, reducedMotion, onDismiss))
    }
}

/** A hairline bar rather than Material's filled pill: the sheet is paper, the handle is a crease. */
@Composable
private fun SheetHandle() {
    Box(
        Modifier.fillMaxWidth().padding(top = Spacing.md, bottom = Spacing.sm),
        contentAlignment = Alignment.Center
    ) {
        Box(Modifier.width(32.dp).height(4.dp).background(Poruch.colors.hairline, Radius.pill))
    }
}

/** Handed to a sheet's content so an answer can put the sheet away before it takes effect. */
@OptIn(ExperimentalMaterial3Api::class)
class PoruchSheetScope internal constructor(
    private val state: SheetState,
    private val scope: CoroutineScope,
    private val reducedMotion: Boolean,
    private val onDismiss: () -> Unit
) {
    /**
     * Slides the sheet out, then reports the dismissal and runs [then]. Dropping the state at the
     * moment of the tap removes the sheet from the screen mid-gesture, so the answer blinks out
     * instead of being put down. With animations switched off there is nothing to wait for.
     */
    fun close(then: () -> Unit = {}) {
        if (reducedMotion) {
            onDismiss(); then(); return
        }
        scope.launch { state.hide() }.invokeOnCompletion {
            if (!state.isVisible) { onDismiss(); then() }
        }
    }
}

/**
 * The one shape a question with two answers takes. The destructive answer is the button — hiding
 * it among equal-weight text labels is how a person cancels an event by accident — and the way
 * out is the quieter one underneath it, next to the drag that also works.
 */
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
