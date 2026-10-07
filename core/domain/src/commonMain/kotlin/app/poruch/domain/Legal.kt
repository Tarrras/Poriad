package app.poruch.domain

/**
 * Адреси юридичних сторінок і підтримки. Сторінки лежать у `site/`; домен — заглушка до появи
 * хостингу, тому все зібрано в одному місці, щоб замінити один раз.
 */
object LegalLinks {
    const val SITE = "https://poriad.app"
    const val TERMS = "$SITE/terms.html"
    const val PRIVACY = "$SITE/privacy.html"
    const val DELETE_ACCOUNT = "$SITE/delete-account.html"
    const val SUPPORT_EMAIL = "hello@poriad.app"
}

/** Сторінки застосунку в сторах. Ділимось сайтом: на ньому обидві кнопки, а друг може бути з іншою ОС. */
object StoreLinks {
    const val ANDROID_PACKAGE = "app.poriad.android"
    const val PLAY = "https://play.google.com/store/apps/details?id=$ANDROID_PACKAGE"
    const val APP_STORE = "https://apps.apple.com/app/id6813543772"
    /** Відкриває одразу форму відгуку в App Store. */
    const val APP_STORE_REVIEW = "$APP_STORE?action=write-review"
    const val SHARE = LegalLinks.SITE
}

/**
 * Посилання на подію: `poriad.app/e/{id}` віддає веб-сторінку з прев'ю (worker/), а на телефоні з
 * застосунком відкриває його (Universal Links / App Links). Кнопка сторінки «Відкрити в застосунку»
 * веде на `{схема}://event/{id}` — з того самого домену iOS універсальне посилання не перехоплює.
 */
object EventLinks {
    fun url(eventId: String) = "${LegalLinks.SITE}/e/$eventId"

    /** Id події з будь-якого з двох посилань; решта (auth-колбек, чужі адреси) — null. */
    fun eventId(link: String): String? = PATTERN.matchEntire(link)?.groupValues?.get(1)?.lowercase()

    private val PATTERN =
        Regex("""(?:https://(?:www\.)?poriad\.app/e/|[a-z][a-z0-9+.-]*://event/)([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})/?(?:[?#].*)?""")
}
