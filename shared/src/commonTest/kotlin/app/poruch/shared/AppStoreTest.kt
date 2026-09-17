package app.poruch.shared

import app.poruch.domain.*
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.*

@OptIn(ExperimentalCoroutinesApi::class)
class AppStoreTest {
    /** Другий тап під час першої зміни — подвійний тап, а не другий намір. */
    @Test fun aSecondMutationWhileOneRunsIsIgnored() = runTest {
        val store = AppStore(AppState(), backgroundScope)
        val gate = CompletableDeferred<Unit>()
        var runs = 0
        store.mutate { runs++; gate.await() }
        store.mutate { runs++ }
        runCurrent()
        assertEquals(1, runs)
        assertTrue(store.value.mutating)
        gate.complete(Unit); runCurrent()
        assertFalse(store.value.mutating)
        store.mutate { runs++ }; runCurrent()
        assertEquals(2, runs, "після завершення наступна зміна проходить")
    }

    /** Збій стає банером, а прапорець зміни знімається в будь-якому разі. */
    @Test fun aFailureBecomesANoticeAndReleasesTheGate() = runTest {
        val store = AppStore(AppState(notice = AppNotice.Told(AppMessage.SIGNED_IN)), backgroundScope)
        store.mutate { fail(AppError.EventFull) }; runCurrent()
        assertEquals(AppNotice.Failed(AppError.EventFull), store.value.notice)
        assertFalse(store.value.mutating)
        // Чужий виняток — проблема сервісу, не падіння застосунку.
        store.mutate { throw IllegalStateException("boom") }; runCurrent()
        assertEquals(AppNotice.Failed(AppError.ServiceUnavailable), store.value.notice)
    }

    /** Початок зміни прибирає старий банер: новий результат не має читатись поверх старого. */
    @Test fun startingAMutationClearsThePreviousNotice() = runTest {
        val store = AppStore(AppState(notice = AppNotice.Told(AppMessage.SIGNED_IN)), backgroundScope)
        store.mutate { }; runCurrent()
        assertNull(store.value.notice)
        store.tell(AppMessage.JOINED_EVENT)
        assertEquals(AppNotice.Told(AppMessage.JOINED_EVENT), store.value.notice)
    }
}
