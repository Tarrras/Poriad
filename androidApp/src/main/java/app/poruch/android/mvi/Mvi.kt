package app.poruch.android.mvi

import androidx.activity.compose.LocalActivity
import androidx.compose.runtime.Composable
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelStoreOwner
import androidx.lifecycle.viewModelScope
import app.poruch.shared.AppState
import app.poruch.shared.PoruchApp
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch

/**
 * Один екран — один цикл: інтенти на вхід, стан на вихід, ефекти для того, що стан не виразить.
 * Composable не кличе стор напряму, тому екран читається сам по собі й тестується без пристрою.
 */
abstract class MviViewModel<State : Any, Intent : Any, Effect : Any>(initial: State) : ViewModel() {
    private val mutable = MutableStateFlow(initial)
    val state: StateFlow<State> = mutable.asStateFlow()

    // Ефекти одноразові: навігація не має повторюватись після повороту, тому канал, а не стан.
    private val channel = Channel<Effect>(Channel.BUFFERED)
    val effects: Flow<Effect> = channel.receiveAsFlow()

    /** Єдиний вхід з UI. */
    fun dispatch(intent: Intent) = onIntent(intent)

    protected abstract fun onIntent(intent: Intent)

    protected fun reduce(block: State.() -> State) = mutable.update(block)

    protected fun send(effect: Effect) {
        viewModelScope.launch { channel.send(effect) }
    }

    /**
     * Потяг вниз: тримає прапорець піднятим, поки [block] не поверне, щоб індикатор знав, коли
     * сховатись. Другий потяг під час першого нічого не робить: запит уже в дорозі.
     */
    protected fun refresh(refreshing: State.() -> Boolean, set: State.(Boolean) -> State, block: suspend () -> Unit) {
        if (state.value.refreshing()) return
        viewModelScope.launch {
            reduce { set(true) }
            try { block() } finally { reduce { set(false) } }
        }
    }

    /** Згортає спільний стор у стан екрана, поки екран живий. */
    protected fun observe(app: PoruchApp, fold: State.(AppState) -> State) {
        viewModelScope.launch { app.state.collect { shared -> reduce { fold(shared) } } }
    }
}

/** Сховище моделей Activity для вкладок і онбордингу: всередині `NavDisplay` кожен запис підставляє власне. */
@Composable
fun activityStoreOwner(): ViewModelStoreOwner =
    LocalActivity.current as? ViewModelStoreOwner ?: error("no Activity to own tab view models")
