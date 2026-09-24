package app.poruch.domain

/**
 * Картка людини, як її віддає `profile_card`. [email] — лише у власній. [memberSince] — ISO-8601.
 * [organized] — опубліковані спільнотні події, [attended] — завершені, куди людину прийняли.
 */
data class Profile(
    val userId: String,
    val name: String,
    val avatarUrl: String?,
    val bio: String?,
    val memberSince: String?,
    val organized: Int,
    val attended: Int,
    val email: String? = null
) {
    val asAttendee get() = Attendee(userId, name, avatarUrl)
}

/** Межі профілю. Сервер перевіряє ті самі (CHECK на bio, стоп-словник у тригері). */
object ProfileRules {
    const val BIO_MAX = 300

    /** Довша сторона фото профілю після перекодування: аватар ніде не більший за 96 pt. */
    const val AVATAR_SIDE = 512

    /** Порожнє «Про себе» — не рядок, а його відсутність: CHECK не пускає порожній. */
    fun normalizeBio(value: String?): String? = value?.trim()?.take(BIO_MAX)?.ifEmpty { null }
}

/** Свій профіль і чужі картки. Видимість вирішує сервер: невидима людина — null. */
interface ProfileRepository {
    suspend fun profile(userId: String): Profile?
    suspend fun update(name: String, bio: String?)

    /** Завантажує фото в теку `avatar` і ставить його в профіль. Повертає нову адресу. */
    suspend fun setAvatar(bytes: ByteArray, contentType: String): String
    suspend fun removeAvatar()

    /** Прибирає файл колишнього фото. Best-effort: сирота зникне з видаленням акаунта. */
    suspend fun deleteImage(url: String)
}
