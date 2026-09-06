package app.poruch.android.mvi

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import app.poruch.shared.AppState
import app.poruch.shared.PoruchApp
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch

/**
 * One screen, one loop: intents in, state out, effects for the things state cannot express.
 *
 * A composable never calls the store directly — it emits an [Intent] and renders the [State] it
 * gets back. That is what makes a screen readable on its own and testable without a device.
 */
abstract class MviViewModel<State : Any, Intent : Any, Effect : Any>(initial: State) : ViewModel() {
    private val mutable = MutableStateFlow(initial)
    val state: StateFlow<State> = mutable.asStateFlow()

    // Effects are one-shot: navigation and system calls must not replay on a configuration change,
    // so they go through a channel rather than living in the state.
    private val channel = Channel<Effect>(Channel.BUFFERED)
    val effects: Flow<Effect> = channel.receiveAsFlow()

    /** The single entry point from the UI. */
    fun dispatch(intent: Intent) = onIntent(intent)

    protected abstract fun onIntent(intent: Intent)

    protected fun reduce(block: State.() -> State) = mutable.update(block)

    protected fun send(effect: Effect) {
        viewModelScope.launch { channel.send(effect) }
    }

    /** Folds the shared store into this screen's state, for as long as the screen lives. */
    protected fun observe(app: PoruchApp, fold: State.(AppState) -> State) {
        viewModelScope.launch { app.state.collect { shared -> reduce { fold(shared) } } }
    }
}

/** The store, provided once at the root so no screen has to be handed it through every layer. */
val LocalPoruchApp = staticCompositionLocalOf<PoruchApp> { error("PoruchApp is not provided") }

/**
 * Builds a screen's ViewModel from the ambient store. [key] separates instances of the same screen
 * on the back stack — two event details are two view models, not one shared by accident.
 */
@Composable
inline fun <reified VM : ViewModel> screenViewModel(key: String? = null, crossinline create: (PoruchApp) -> VM): VM {
    val app = LocalPoruchApp.current
    val factory = remember(app) {
        object : ViewModelProvider.Factory {
            @Suppress("UNCHECKED_CAST")
            override fun <T : ViewModel> create(modelClass: Class<T>): T = create(app) as T
        }
    }
    return viewModel(key = key, factory = factory)
}
