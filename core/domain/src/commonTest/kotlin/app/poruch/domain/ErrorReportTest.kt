package app.poruch.domain

import kotlinx.serialization.SerializationException
import kotlin.test.*

class ErrorReportTest {
    /** Відмова, яку ми вже назвали, — не баг; чужий виняток — баг і йде в звіт зі своїм винятком. */
    @Test fun onlyForeignExceptionsAreReported() {
        val reported = mutableListOf<Pair<String, Throwable?>>()
        PoruchLog.reporter = { issue, error -> reported += issue to error }
        try {
            assertEquals(AppError.EventFull, AppFailure(AppError.EventFull).asAppError())
            val bug = IllegalStateException("state")
            assertEquals(AppError.ServiceUnavailable, bug.asAppError())
            assertEquals(listOf<Pair<String, Throwable?>>("unexpected: IllegalStateException" to bug), reported)
        } finally {
            PoruchLog.reporter = null
        }
    }

    /** Суть збою розбору лишається, JSON із чужими даними — ні; `message` інших винятків не виходить. */
    @Test fun summaryKeepsParseDetailWithoutPayload() {
        val parse = SerializationException("Field 'title' is required, but it was missing at path: $[0]\nJSON input: {\"name\":\"Олена\"}")
        assertEquals("SerializationException: Field 'title' is required, but it was missing at path: $[0]", parse.summary())
        assertEquals("IllegalStateException", IllegalStateException("https://x/rest/v1/events?id=eq.123").summary())
    }
}
