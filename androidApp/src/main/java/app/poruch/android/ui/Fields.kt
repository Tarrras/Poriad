package app.poruch.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.error
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.poruch.android.R

@Composable
fun PoruchSearchField(
    value: String, onValueChange: (String) -> Unit, placeholder: String,
    modifier: Modifier = Modifier, activeFilters: Int = 0, onFilters: (() -> Unit)? = null,
    /** Поле з'явилося на вимогу людини (іконка пошуку): курсор одразу в ньому. */
    autoFocus: Boolean = false
) {
    val colors = Poruch.colors
    val focus = remember { FocusRequester() }
    if (autoFocus) LaunchedEffect(Unit) { focus.requestFocus() }
    Row(
        modifier,
        horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Row(
            Modifier
                .weight(1f)
                .height(50.dp)
                .cardSurface(Radius.pill, Elevation.card)
                .padding(horizontal = Spacing.lg),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Spacing.md)
        ) {
            Icon(PoruchIcons.search, null, Modifier.size(18.dp), tint = colors.inkSecondary)
            BasicTextField(
                value = value,
                onValueChange = onValueChange,
                singleLine = true,
                modifier = Modifier
                    .weight(1f)
                    .focusRequester(focus),
                textStyle = MaterialTheme.typography.bodyLarge.copy(color = colors.ink),
                cursorBrush = SolidColor(colors.ink),
                decorationBox = { inner ->
                    if (value.isEmpty()) Text(
                        placeholder,
                        style = MaterialTheme.typography.bodyLarge,
                        color = colors.inkTertiary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    inner()
                }
            )
            // Значок дрібний, зона дотику повна: у 18 dp не влучиш.
            if (value.isNotEmpty()) Box(
                Modifier
                    .minimumInteractiveComponentSize()
                    .clip(CircleShape)
                    .clickable { onValueChange("") },
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    PoruchIcons.closeCircle, stringResource(R.string.clear_search),
                    Modifier.size(18.dp), tint = colors.inkTertiary
                )
            }
        }
        if (onFilters != null) Box {
            IconPill(PoruchIcons.filters, stringResource(R.string.filters), onClick = onFilters)
            if (activeFilters > 0) Text(
                activeFilters.toString(),
                style = MaterialTheme.typography.labelSmall,
                color = colors.onBrand,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .size(18.dp)
                    .background(colors.accentText, CircleShape)
                    .wrapContentSize(Alignment.Center)
            )
        }
    }
}

@Composable
fun PoruchField(
    value: String, onValueChange: (String) -> Unit, label: String, modifier: Modifier = Modifier,
    singleLine: Boolean = true, error: String? = null, supporting: String? = null,
    /** Фокус для екрана, що відкривається заради цього поля. [modifier] лягає на колонку, а фокус потрібен введенню. */
    focusRequester: FocusRequester? = null
) {
    val colors = Poruch.colors
    val field = rememberBufferedText(value, onValueChange)
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
        OutlinedTextField(
            value = field.text,
            onValueChange = field.onChange,
            label = { Text(label) },
            singleLine = singleLine,
            minLines = if (singleLine) 1 else 4,
            isError = error != null,
            shape = Radius.sm,
            modifier = Modifier.fillMaxWidth()
                .let { if (focusRequester != null) it.focusRequester(focusRequester) else it },
            colors = OutlinedTextFieldDefaults.colors(
                focusedContainerColor = colors.surface,
                unfocusedContainerColor = colors.surface,
                focusedBorderColor = colors.ink,
                unfocusedBorderColor = colors.hairline,
                focusedTextColor = colors.ink,
                unfocusedTextColor = colors.ink,
                focusedLabelColor = colors.ink,
                unfocusedLabelColor = colors.inkTertiary,
                cursorColor = colors.ink
            )
        )
        (error ?: supporting)?.let {
            Text(
                it,
                style = MaterialTheme.typography.bodySmall,
                color = if (error != null) colors.danger else colors.inkTertiary,
                modifier = Modifier.padding(start = Spacing.lg)
            )
        }
    }
}

/** Поле з малим підписом над рамкою замість плаваючого плейсхолдера Material: форма читається як список названих речей. */
@Composable
fun LabelledField(
    label: String, value: String, onValueChange: (String) -> Unit, modifier: Modifier = Modifier,
    placeholder: String = "", singleLine: Boolean = true, hint: String? = null,
    /** Багаторядкове поле відкривається цієї висоти, щоб читалось як місце для абзацу. */
    minLines: Int = if (singleLine) 1 else 4,
    keyboardOptions: KeyboardOptions = KeyboardOptions.Default,
    visualTransformation: VisualTransformation = VisualTransformation.None,
    /** Фокус для екрана, що відкривається заради цього поля. */
    focusRequester: FocusRequester? = null,
    /** Що не так із полем: під ним, кольором помилки. */
    error: String? = null,
    trailing: @Composable (() -> Unit)? = null
) {
    val colors = Poruch.colors
    val field = rememberBufferedText(value, onValueChange)
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        // Підпис — назва самого поля для TalkBack, а не окрема зупинка перед ним: інакше заповнене поле
        // озвучувало лише значення, без того, що це за поле.
        Text(
            label.uppercase(),
            style = MaterialTheme.typography.labelSmall,
            color = colors.inkTertiary,
            modifier = Modifier.clearAndSetSemantics { }
        )
        Row(
            // Висота вміщує 48 dp ціль кінцевого контролу, не переростаючи сусіднє поле.
            Modifier
                .fillMaxWidth()
                .defaultMinSize(minHeight = 56.dp)
                // Біле поле на сірому полотні: `surfaceMuted` відрізнявся від полотна на два тони і поле зникало.
                // У шторці навпаки — див. [LocalFieldSurface].
                .background(LocalFieldSurface.current ?: colors.surface, Radius.sm)
                .padding(horizontal = Spacing.lg, vertical = if (singleLine) 0.dp else Spacing.md),
            verticalAlignment = if (singleLine) Alignment.CenterVertically else Alignment.Top,
            horizontalArrangement = Arrangement.spacedBy(Spacing.sm)
        ) {
            BasicTextField(
                value = field.text,
                onValueChange = field.onChange,
                singleLine = singleLine,
                minLines = minLines,
                modifier = Modifier.weight(1f)
                    // Помилка — стан поля: TalkBack каже її разом із назвою, а не як окремий текст нижче.
                    .semantics { contentDescription = label; if (error != null) error(error) }
                    .let { if (focusRequester != null) it.focusRequester(focusRequester) else it },
                textStyle = MaterialTheme.typography.bodyLarge.copy(color = colors.ink),
                cursorBrush = SolidColor(colors.ink),
                keyboardOptions = keyboardOptions,
                visualTransformation = visualTransformation,
                decorationBox = { inner ->
                    if (field.text.isEmpty() && placeholder.isNotEmpty()) {
                        Text(
                            placeholder,
                            style = MaterialTheme.typography.bodyLarge,
                            color = colors.inkTertiary
                        )
                    }
                    inner()
                }
            )
            trailing?.invoke()
        }
        hint?.let {
            Text(
                it,
                style = MaterialTheme.typography.bodySmall,
                color = colors.inkTertiary
            )
        }
        error?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = colors.danger) }
    }
}

/**
 * Перемикач видимості пароля для [LabelledField]. Іконка — стан, як у системному полі Android:
 * відкрите око, коли пароль видно, перекреслене — коли приховано. Підпис для TalkBack — дія.
 */
@Composable
fun PasswordRevealIcon(revealed: Boolean, onToggle: () -> Unit) {
    Icon(
        if (revealed) PoruchIcons.eye else PoruchIcons.eyeOff,
        stringResource(if (revealed) R.string.hide_password else R.string.show_password),
        Modifier
            .minimumInteractiveComponentSize()
            .size(20.dp)
            .clip(CircleShape)
            .clickable(onClick = onToggle),
        tint = Poruch.colors.inkSecondary
    )
}

/** Поле з вибором замість введення: дата, місце. Виглядає як [LabelledField], щоб форма лишалась одним списком. */
@Composable
fun PickerField(
    label: String, value: String, onClick: () -> Unit, modifier: Modifier = Modifier,
    placeholder: String = "", hint: String? = null, icon: ImageVector? = null
) {
    val colors = Poruch.colors
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        Text(
            label.uppercase(),
            style = MaterialTheme.typography.labelSmall,
            color = colors.inkTertiary
        )
        Row(
            Modifier
                .fillMaxWidth()
                .defaultMinSize(minHeight = 56.dp)
                // Біле поле на сірому полотні: `surfaceMuted` відрізнявся від полотна на два тони і поле зникало.
                // У шторці навпаки — див. [LocalFieldSurface].
                .background(LocalFieldSurface.current ?: colors.surface, Radius.sm)
                .clip(Radius.sm)
                .pressable(onClick = onClick)
                .padding(horizontal = Spacing.lg),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Spacing.sm)
        ) {
            Text(
                value.ifEmpty { placeholder },
                style = MaterialTheme.typography.bodyLarge,
                color = if (value.isEmpty()) colors.inkTertiary else colors.ink,
                modifier = Modifier.weight(1f)
            )
            icon?.let { Icon(it, null, Modifier.size(18.dp), tint = colors.inkTertiary) }
        }
        hint?.let {
            Text(
                it,
                style = MaterialTheme.typography.bodySmall,
                color = colors.inkTertiary
            )
        }
    }
}

/**
 * Буфер для поля, чиє значення живе у ViewModel: відлуння зі стору приходить на кадр пізніше і
 * при швидкому наборі губило б символи. Буфер приймає вхідне значення лише коли це не відлуння
 * останньої правки (скидання, відновлена чернетка).
 */
@Composable
fun rememberBufferedText(value: String, onValueChange: (String) -> Unit): BufferedText {
    var text by remember { mutableStateOf(value) }
    var sent by remember { mutableStateOf(value) }
    if (value != sent) {
        text = value; sent = value
    }
    return BufferedText(text) { edited ->
        text = edited
        sent = edited
        onValueChange(edited)
    }
}

class BufferedText(val text: String, val onChange: (String) -> Unit)

/**
 * Перемикач у кольорах токенів. Стандартний вимкнений стан бере `surfaceContainerHighest`, якого
 * в нашій схемі нема, і на теплому папері виглядав як сіра пляма без бігунка.
 */
@Composable
fun PoruchSwitch(
    checked: Boolean,
    /** Null — перемикає весь рядок (`toggleable`), і TalkBack читає підпис рядка разом зі станом. */
    onCheckedChange: ((Boolean) -> Unit)?,
    modifier: Modifier = Modifier
) {
    val colors = Poruch.colors
    Switch(
        checked, onCheckedChange, modifier,
        colors = SwitchDefaults.colors(
            checkedTrackColor = colors.brand,
            checkedThumbColor = colors.onBrand,
            checkedBorderColor = colors.brand,
            uncheckedTrackColor = colors.surfaceMuted,
            uncheckedThumbColor = colors.inkTertiary,
            uncheckedBorderColor = colors.hairline
        )
    )
}
