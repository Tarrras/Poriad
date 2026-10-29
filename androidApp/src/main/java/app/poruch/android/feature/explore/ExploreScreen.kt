package app.poruch.android.feature.explore

import androidx.compose.animation.*
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import app.poruch.android.EventMap
import app.poruch.android.LocalSharedMapView
import app.poruch.android.R
import app.poruch.android.ui.*
import app.poruch.shared.DateFilter
import kotlinx.coroutines.delay

/** Висота градієнта під верхніми контролами і відступ мапи під ними. */
internal val TopControlsInset = 152.dp
/** Смуга шторки, з каруселлю чи порожньою карткою. */
internal val CarouselInset = 268.dp

@Composable
fun ExploreScreen(state: ExploreState, onIntent: (ExploreIntent) -> Unit) {
    val colors = Poruch.colors
    // Повна шторка накриває мапу й верхні контроли: TalkBack не має ходити по невидимому.
    val covered = state.detent == SheetDetent.FULL
    BoxWithConstraints(Modifier.fillMaxSize().background(colors.canvas)) {
        EventMap(
            events = state.screen.mapEvents, latitude = state.screen.cityLatitude, longitude = state.screen.cityLongitude,
            selectedId = state.screen.selectedId, topInset = TopControlsInset, bottomInset = CarouselInset,
            centerToken = state.recenterToken, retryToken = state.retryToken, district = state.screen.district,
            onSelect = { onIntent(ExploreIntent.SelectEvent(it)) },
            onSelectStack = { onIntent(ExploreIntent.SelectStack(it)) },
            onAreaChanged = { onIntent(ExploreIntent.AreaMoved(it?.let { b -> Area(b.south, b.west, b.north, b.east) })) },
            onViewportChanged = { onIntent(ExploreIntent.Viewport(Area(it.south, it.west, it.north, it.east))) },
            onLoadFailed = { onIntent(ExploreIntent.MapFailed(it)) },
            shared = LocalSharedMapView.current,
            hiddenFromAccessibility = covered
        )
        Box(
            Modifier.fillMaxWidth().height(TopControlsInset)
                .background(Brush.verticalGradient(listOf(colors.canvas.copy(alpha = 0.94f), colors.canvas.copy(alpha = 0f))))
        )
        Box(if (covered) Modifier.clearAndSetSemantics {} else Modifier) { TopControls(state, onIntent) }
        // На широкому вікні шторка — колонкою по центру, як решта екранів, а не на всю ширину мапи.
        DiscoverySheet(state, maxHeight, Modifier.align(Alignment.BottomCenter).widthIn(max = ContentMaxWidth), onIntent)
    }

    when (state.sheet) {
        ExploreSheet.CITY -> CitySearchSheet(
            state.screen.cityName, state.screen.cities, { onIntent(ExploreIntent.SearchCity(it)) },
            { onIntent(ExploreIntent.SelectCity(it)) }, { onIntent(ExploreIntent.ShowSheet(ExploreSheet.NONE)) }
        )
        ExploreSheet.FILTERS -> PoruchSheet({ onIntent(ExploreIntent.ShowSheet(ExploreSheet.NONE)) }) { sheet ->
            FilterSheet(state, onIntent) { sheet.close() }
        }
        ExploreSheet.DISTRICTS -> PoruchSheet({ onIntent(ExploreIntent.ShowSheet(ExploreSheet.NONE)) }) { sheet ->
            DistrictSheet(state, { hit -> sheet.close { onIntent(ExploreIntent.PickDistrict(hit)) } }) { hit ->
                onIntent(ExploreIntent.ToggleDistrictZone(hit))
            }
        }
        ExploreSheet.NONE -> Unit
    }
    // Чесно: без геолокації «ближче» не порахувати, список лишився «для вас». Вихід — дозвіл у налаштуваннях.
    if (state.nearDenied) PoruchSheet({ onIntent(ExploreIntent.DismissNearDenied) }) { sheet ->
        Column(
            Modifier.padding(horizontal = Spacing.page).padding(bottom = Spacing.section),
            verticalArrangement = Arrangement.spacedBy(Spacing.md)
        ) {
            Text(stringResource(R.string.location_title), style = PoruchType.brandTitle2, color = colors.ink)
            Text(
                stringResource(R.string.nearer_me_denied), style = MaterialTheme.typography.bodyLarge,
                color = colors.inkSecondary, modifier = Modifier.padding(bottom = Spacing.sm)
            )
            PrimaryButton(
                stringResource(R.string.open_settings), { sheet.close { onIntent(ExploreIntent.OpenLocationSettings) } },
                Modifier.fillMaxWidth()
            )
            SecondaryButton(stringResource(R.string.close), { sheet.close() }, Modifier.fillMaxWidth())
        }
    }
    // Підказка першого знайомства: де список і що таке пін із числом. Лише над згорнутою шторкою з картками,
    // коли поверх мапи нічого не відкрито.
    CoachMarks(
        listOf(CoachTip.SHEET),
        enabled = state.detent == SheetDetent.PEEK && state.sheet == ExploreSheet.NONE && state.screen.deckEvents.isNotEmpty()
    )
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun TopControls(state: ExploreState, onIntent: (ExploreIntent) -> Unit) {
    val colors = Poruch.colors
    // Дата, обрана у «Фільтрах», лягала за край ряду, і видно було лише цифру на кнопці.
    val pickedDate = remember { BringIntoViewRequester() }
    LaunchedEffect(state.screen.dateFilter) { if (state.screen.dateFilter != DateFilter.ANY) pickedDate.bringIntoView() }
    // Поле тримає набране само, а нагору шле після паузи, як `SearchBar` на iOS: значення зі стану презентера (інший потік)
    // приходило на кадр пізніше, і Compose повертав поле й IME на старий текст. Текст ззовні (заклад з пошуку) поле бере.
    val shared = state.screen.searchText
    var text by rememberSaveable { mutableStateOf(shared) }
    var sent by rememberSaveable { mutableStateOf(shared) }
    LaunchedEffect(shared) { if (shared != sent) { sent = shared; text = shared } }
    LaunchedEffect(text) {
        if (text == sent) return@LaunchedEffect
        delay(SEARCH_SETTLE_MS)
        sent = text
        onIntent(ExploreIntent.Search(text))
    }
    val changeCity = stringResource(R.string.a11y_change_city)
    Column(Modifier.statusBarsPadding().padding(vertical = Spacing.page), verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
        PoruchSearchField(
            text, { text = it }, stringResource(R.string.search_placeholder),
            Modifier.padding(horizontal = Spacing.page),
            activeFilters = state.screen.activeFilters, onFilters = { onIntent(ExploreIntent.ShowSheet(ExploreSheet.FILTERS)) }
        )
        // Один ряд замість двох: місто веде стрічку фільтрів. Керування мапою — над каруселлю, під пальцем. Від краю до
        // краю, поля — всередині прокрутки, як на iOS.
        Row(
            Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = Spacing.page),
            horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalAlignment = Alignment.CenterVertically
        ) {
            // Назва — видимий текст («Київ»), а що робить — підписом дії, як підказка на iOS.
            val openCity = { onIntent(ExploreIntent.ShowSheet(ExploreSheet.CITY)) }
            Box(Modifier.clearAndSetSemantics {
                contentDescription = state.screen.cityName; role = Role.Button
                onClick(label = changeCity) { openCity(); true }
            }) {
                PoruchChip(state.screen.cityName, false, openCity, PoruchIcons.pin, trailingIcon = PoruchIcons.chevronDown)
            }
            // Район — одразу за містом: це його частина («Одеса», «Київський район»). Тап знімає, як категорію.
            state.screen.district?.let { district ->
                val description = stringResource(R.string.a11y_clear_district, district.name)
                val clear = { onIntent(ExploreIntent.ClearDistrict) }
                Box(Modifier.clearAndSetSemantics { contentDescription = description; role = Role.Button; onClick { clear(); true } }) {
                    PoruchChip(district.shortName, true, clear, PoruchIcons.district, trailingIcon = PoruchIcons.close)
                }
            }
            // Набране — назва району: підказка тут, під пальцем, а не лише в піднятій шторці. У згорнутій карусель
            // показувала б «подій нема» за словом «Київський», хоча район є. Тап — той самий вибір, що рядком.
            val suggested = state.screen.districts.firstOrNull()?.takeIf { it.district != state.screen.district }
            suggested?.let { hit ->
                val description = stringResource(R.string.a11y_suggest_district, hit.district.name)
                val pick = { onIntent(ExploreIntent.SelectDistrict(hit)) }
                Box(Modifier.clearAndSetSemantics { contentDescription = description; role = Role.Button; onClick { pick(); true } }) {
                    PoruchChip(hit.district.name, false, pick, PoruchIcons.district)
                }
            }
            // Без набору: «Район ⌄» відкриває райони міста, як «Категорія ⌄» — плитки. Є, поки район не обрано й не
            // підказано за словом.
            if (state.screen.district == null && suggested == null && state.screen.cityDistricts.isNotEmpty()) {
                val description = stringResource(R.string.a11y_pick_district)
                val open = { onIntent(ExploreIntent.ShowSheet(ExploreSheet.DISTRICTS)) }
                Box(Modifier.clearAndSetSemantics { contentDescription = description; role = Role.Button; onClick { open(); true } }) {
                    PoruchChip(stringResource(R.string.district_chip), false, open, PoruchIcons.district, trailingIcon = PoruchIcons.chevronDown)
                }
            }
            // Одразу після міста, а не за датами: з «Усі N» головної мапа приходить із цим фільтром, і його має бути видно.
            PoruchChip(
                stringResource(R.string.home_with_whom), state.screen.onlyAvailable,
                { onIntent(ExploreIntent.OnlyAvailable(!state.screen.onlyAvailable)) }, PoruchIcons.social
            )
            // Категорію з «Фільтрів» чи плиток видно тут, а не лише цифрою на кнопці фільтрів. Тап знімає її. Поруч із датами:
            // коли ряд доїжджає до обраної дати, категорія лишається видно.
            state.screen.category?.let { category ->
                val label = stringResource(categoryLabel(category))
                val description = stringResource(R.string.a11y_clear_category, label)
                val clear = { onIntent(ExploreIntent.PickCategory(null)) }
                Box(Modifier.clearAndSetSemantics { contentDescription = description; role = Role.Button; onClick { clear(); true } }) {
                    PoruchChip(label, true, clear, dot = category, trailingIcon = PoruchIcons.close)
                }
            }
            // «Будь-коли» лише у «Фільтрах»: тут повторний тап і так знімає дату, а зайвий чип виштовхував обрану за край.
            dateFilters.filter { it.first != DateFilter.ANY }.forEach { (key, label) ->
                val selected = state.screen.dateFilter == key
                Box(if (selected) Modifier.bringIntoViewRequester(pickedDate) else Modifier) {
                    PoruchChip(stringResource(label), selected, {
                        onIntent(ExploreIntent.PickDate(if (selected) DateFilter.ANY else key))
                    })
                }
            }
        }
        if (state.locationDenied) Text(
            stringResource(R.string.location_fallback), style = MaterialTheme.typography.bodySmall, color = colors.ink,
            modifier = Modifier.padding(horizontal = Spacing.page).cardSurface(Radius.sm).padding(Spacing.md)
        )
        AreaPrompts(state, Modifier.align(Alignment.CenterHorizontally), onIntent)
    }
}

/** «Шукати тут» і повтор після збою мапи. У тій самій колонці, що й контроли: окремий шар зі зсувом перекривав чипи дат. */
@Composable
private fun AreaPrompts(state: ExploreState, modifier: Modifier, onIntent: (ExploreIntent) -> Unit) {
    Column(
        modifier,
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Spacing.sm)
    ) {
        // Скидання з порожньої картки прибирає одразу кілька фільтрів: повернути їх — тим самим жестом, без пошуку.
        AnimatedVisibility(state.undoFilters != null, enter = fadeIn(), exit = fadeOut()) {
            Row(
                Modifier.heightIn(min = 48.dp).cardSurface(Radius.pill, Elevation.raised)
                    .clickable(role = Role.Button) { onIntent(ExploreIntent.UndoReset) }
                    .padding(horizontal = Spacing.lg),
                horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalAlignment = Alignment.CenterVertically
            ) {
                Text(stringResource(R.string.filters_reset), style = MaterialTheme.typography.labelMedium, color = Poruch.colors.inkSecondary)
                Text(stringResource(R.string.undo), style = MaterialTheme.typography.labelLarge, color = Poruch.colors.ink)
            }
        }
        AnimatedVisibility(
            state.pendingArea != null,
            enter = if (Poruch.reducedMotion) fadeIn() else fadeIn() + scaleIn(initialScale = 0.9f),
            exit = if (Poruch.reducedMotion) fadeOut() else fadeOut() + scaleOut(targetScale = 0.9f)
        ) {
            PrimaryButton(stringResource(R.string.search_here), { onIntent(ExploreIntent.SearchHere) }, icon = PoruchIcons.refresh)
        }
        // Пігулка з повтором, як на iOS: стиль завантажується знову, а не лише камера їде до міста.
        if (state.mapFailed) Row(
            Modifier.heightIn(min = 48.dp).cardSurface(Radius.pill, Elevation.raised)
                .clickable(role = Role.Button) { onIntent(ExploreIntent.RetryMap) }
                .padding(horizontal = Spacing.lg),
            horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(PoruchIcons.refresh, null, Modifier.size(16.dp), tint = Poruch.colors.ink)
            Text(stringResource(R.string.map_error_short), style = MaterialTheme.typography.labelLarge, color = Poruch.colors.ink)
        }
    }
}

/** Пауза після набору перед пошуком: як `searchSettle` на iOS. */
internal const val SEARCH_SETTLE_MS = 250L

internal val dateFilters = listOf(
    DateFilter.ANY to R.string.any_date,
    DateFilter.TODAY to R.string.today,
    DateFilter.TOMORROW to R.string.tomorrow,
    DateFilter.WEEKEND to R.string.weekend
)
