package app.poruch.shared

import app.poruch.domain.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

/**
 * Свій профіль (імʼя, «Про себе», фото) і картка чужої людини. Свій профіль вантажить [UserLibrary]
 * разом із «моїми»; тут — зміни й відкрита картка.
 */
internal class ProfileUseCases(
    private val profiles: ProfileRepository?,
    private val store: AppStore,
    private val scope: CoroutineScope
) {
    private var personJob: Job? = null

    private fun repository() = (profiles ?: fail(AppError.ServiceUnavailable)).also {
        if (!store.value.signedIn) fail(AppError.SessionRequired)
    }

    /**
     * Імʼя, «Про себе» й фото однією дією: «Скасувати» в шторці нічого не лишає напівзбереженим.
     * Текст іде першим — стоп-словник сервера може відмовити, і тоді фото не міняється. Нове фото
     * спершу стає профілем, потім зникає старий файл, інакше збій лишив би профіль без фото.
     */
    fun save(name: String, bio: String?, photo: ByteArray?, photoType: String?, removePhoto: Boolean, instagram: String? = null) = store.mutate {
        val repository = repository()
        if (!AccountRules.isName(name)) fail(AppError.InvalidName)
        // Instagram — до всього: зіпсований нікнейм не має лишити ім'я збереженим, а поле — ні.
        val handle = instagram?.let(CompanyRules::normalizeInstagram)
        if (handle != null && !CompanyRules.isValidInstagram(handle)) fail(AppError.Rejected)
        repository.update(name, bio)
        own { copy(name = name.trim(), bio = ProfileRules.normalizeBio(bio)) }
        if (handle != null && handle != store.value.library.profile?.instagram.orEmpty()) {
            repository.setInstagram(handle)
            own { copy(instagram = handle.ifEmpty { null }) }
        }
        val previous = store.value.library.profile?.avatarUrl
        if (photo != null) {
            val url = repository.setAvatar(photo, photoType ?: "image/jpeg")
            own { copy(avatarUrl = url) }
            previous?.let { forget(repository, it) }
        } else if (removePhoto && previous != null) {
            repository.removeAvatar()
            own { copy(avatarUrl = null) }
            forget(repository, previous)
        }
        store.tell(AppMessage.CHANGES_SAVED)
    }

    /** Картка людини. Запізніла відповідь для іншої людини відкидається; невидима людина — порожня картка. */
    fun open(userId: String) {
        personJob?.cancel()
        store.update { it.copy(person = PersonState(userId)) }
        personJob = scope.launch {
            val profile = try {
                profiles?.profile(userId)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                store.failed(e.asAppError()); null
            }
            PoruchLog.d("profile") { "card ${userId.shortId()} ${if (profile == null) "unavailable" else "loaded"}" }
            store.update { if (it.person?.userId == userId) it.copy(person = PersonState(userId, profile, loading = false)) else it }
        }
    }

    fun close() {
        personJob?.cancel()
        store.update { it.copy(person = null) }
    }

    private fun own(change: Profile.() -> Profile) =
        store.update { it.copy(library = it.library.copy(profile = it.library.profile?.change())) }

    private suspend fun forget(repository: ProfileRepository, url: String) {
        try { repository.deleteImage(url) } catch (e: CancellationException) { throw e } catch (e: Exception) {
            PoruchLog.w("profile") { "old avatar not removed: ${e.asAppError()}" }
        }
    }
}
