package app.poruch.shared

import app.poruch.domain.*

/**
 * Відповіді онбордингу, інтереси й нагадування. Зберігаються на пристрої, щоб мав і гість; акаунт
 * переносить лише категорії на інший пристрій.
 */
internal class TasteUseCases(
    private val tasteStore: TasteStore?,
    private val preferences: PreferencesRepository?,
    private val reminderStore: ReminderPreferenceStore?,
    private val store: AppStore,
    private val analyticsStore: AnalyticsPreferenceStore? = null
) {
    /** Словник перевіряємо тут, а не довіряємо екрану. */
    fun save(interests: List<String>, times: List<String>, crowd: String) = store.mutate {
        val answered = Taste(
            interests = interests.filter(EventRules::isCategory).distinct(),
            times = times.filter(TimeSlot::isSlot).distinct(),
            crowd = crowd.takeIf(Crowd::isCrowd) ?: Crowd.ANY,
            answered = true
        )
        PoruchLog.i("taste") {
            "answered: ${answered.interests.size} interests, ${answered.times.size} slots, crowd=${answered.crowd}"
        }
        apply(answered)
        if (store.value.signedIn) preferences?.setInterests(answered.interests)
    }

    /** «Не зараз»: питання закриті, ранжуємо лише за часом. */
    fun skipOnboarding() {
        PoruchLog.i("taste") { "onboarding skipped" }
        apply(store.value.taste.copy(answered = true))
    }

    /** Знову відкриває питання з профілю, з поточними відповідями як початковими. */
    fun restartOnboarding() = apply(store.value.taste.copy(answered = false))

    fun toggleInterest(category: String) = store.mutate {
        if (!EventRules.isCategory(category)) return@mutate
        val selected = store.value.taste.interests
        val next = if (category in selected) selected - category else selected + category
        apply(store.value.taste.copy(interests = next))
        if (store.value.signedIn) preferences?.setInterests(next)
    }

    /** Дозвіл системи — справа платформи: сюди приходить уже результат, план рахує [ReminderSync]. */
    fun setRemindersEnabled(enabled: Boolean) {
        PoruchLog.i("reminders") { if (enabled) "enabled" else "disabled" }
        reminderStore?.setEnabled(enabled)
        store.update { it.copy(remindersEnabled = enabled) }
    }

    /** Згода на аналітику: пристрій, стан і платформний перемикач збору одним рухом. */
    fun setAnalyticsEnabled(enabled: Boolean) {
        PoruchLog.i("analytics") { if (enabled) "enabled" else "disabled" }
        analyticsStore?.setEnabled(enabled)
        PoruchAnalytics.enabled = enabled
        store.update { it.copy(analyticsEnabled = enabled) }
    }

    /** Змінені відповіді належать тому, хто їх змінив: гостю (null) чи поточному акаунту. */
    private fun apply(taste: Taste) {
        val owned = taste.copy(interestsOwner = store.value.session.userId)
        tasteStore?.write(owned)
        store.update { it.copy(taste = owned).ranked() }
    }
}
