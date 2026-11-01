package app.poruch.domain

/** Фото чи відео, як їх називає `events.media[].kind`. */
enum class MediaKind(val key: String) {
    PHOTO("photo"), VIDEO("video");

    companion object {
        /** Невідомий вид (сервер новіший) — null: такий файл не показуємо. */
        fun fromKey(key: String?): MediaKind? = entries.firstOrNull { it.key == key }
    }
}

/**
 * Фото чи відео події (`events.media`, docs/organizers-1.5.md, 1.3). [poster] — перший кадр відео в JPEG; у фото null.
 * Обкладинка ([Event.imageUrl]) — перше фото, а без фото — постер першого відео: її ставить сервер.
 */
data class EventMedia(val kind: MediaKind, val url: String, val poster: String? = null)

/**
 * Фото чи відео в чернетці. Файли вантажаться лише з публікацією: сховище пускає файл лише до наявної події
 * (`private.owns_image_path`), тож гість до входу тримає їх на телефоні.
 */
sealed interface DraftMedia {
    val kind: MediaKind

    /** Уже в цієї події на сервері: редагування. */
    data class Remote(val media: EventMedia) : DraftMedia {
        override val kind get() = media.kind
    }

    /** Іншої події («Повторити»): з публікацією копіюється в теку нової, тож видалення старої її не зачепить. */
    data class Copied(val media: EventMedia) : DraftMedia {
        override val kind get() = media.kind
    }

    /**
     * На телефоні, уже стиснене платформою: фото — JPEG без метаданих до [ImageRules.MAX_BYTES], відео — mp4 H.264 до
     * [MediaRules.VIDEO_MAX_BYTES] з [poster] (перший кадр, JPEG). Байти — на вимогу ([MediaBytes]), тож у пам'яті лише
     * файл, що вантажиться. [key] дає платформа (імʼя файлу, uuid): за ним порівнюємо, бо відбиток чернетки
     * ([CreationIdentityStore]) не має залежати від байтів.
     */
    class Local(val key: String, override val kind: MediaKind, val bytes: MediaBytes, val poster: MediaBytes? = null) : DraftMedia {
        override fun equals(other: Any?) = other is Local && other.key == key && other.kind == kind
        override fun hashCode() = key.hashCode()
        override fun toString() = "Local(${kind.key} $key)"
    }
}

/**
 * Байти файлу чернетки, коли їх вантажать: платформа читає стиснений файл з диска. Кличеться не на головному потоці.
 * На iOS — клас, що реалізує протокол `MediaBytes`; на Android — `MediaBytes { file.readBytes() }`.
 */
fun interface MediaBytes {
    fun read(): ByteArray
}

object MediaRules {
    /** До 5 фото чи відео (`private.assert_media`). */
    const val MAX_ITEMS = 5

    /**
     * Відео після стиснення на телефоні: H.264 720p, ≈ 2 Мбіт/с, перші [VIDEO_MAX_SECONDS] с. Бакет `event-videos` приймає
     * до 50 МБ, але це для вебу без стиснення: кожен перегляд — наш трафік Storage.
     */
    const val VIDEO_MAX_BYTES = 8 * 1024 * 1024
    const val VIDEO_MAX_SECONDS = 30
}
