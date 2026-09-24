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

    fun save(name: String, bio: String?) = store.mutate {
        val repository = repository()
        if (!AccountRules.isName(name)) fail(AppError.InvalidName)
        repository.update(name, bio)
        own { copy(name = name.trim(), bio = ProfileRules.normalizeBio(bio)) }
        store.tell(AppMessage.CHANGES_SAVED)
    }

    /** Нове фото: спершу стає профілем, потім зникає старий файл, інакше збій лишив би профіль без фото. */
    fun setAvatar(bytes: ByteArray, contentType: String) = store.mutate {
        val repository = repository()
        val previous = store.value.library.profile?.avatarUrl
        val url = repository.setAvatar(bytes, contentType)
        own { copy(avatarUrl = url) }
        previous?.let { forget(repository, it) }
        store.tell(AppMessage.PHOTO_ADDED)
    }

    fun removeAvatar() = store.mutate {
        val repository = repository()
        val previous = store.value.library.profile?.avatarUrl ?: return@mutate
        repository.removeAvatar()
        own { copy(avatarUrl = null) }
        forget(repository, previous)
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
