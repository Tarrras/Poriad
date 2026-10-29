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

    /** З токеном «Покликати з собою» (docs/invites.md): та сама сторінка каже «… кличе тебе». Без токена — [url]. */
    fun url(eventId: String, invite: String?) = url(eventId) + if (invite != null) "?by=$invite" else ""

    /** Id події з будь-якого з двох посилань; решта (auth-колбек, чужі адреси) — null. */
    fun eventId(link: String): String? = PATTERN.matchEntire(link)?.groupValues?.get(1)?.lowercase()

    /** Токен запрошення з посилання на подію (`?by=`), з обох видів; токен не того формату — null. */
    fun invite(link: String): String? = PATTERN.matchEntire(link)?.groupValues?.get(2)?.takeIf { it.isNotEmpty() }

    /**
     * Сайт продавця з `utm_source=poriad`: продавець бачить у своїй аналітиці, скільки покупців привела афіша. Решта
     * посилання — як була, свій `utm_source` не перебиваємо. Те саме на сайті — `ticketHref` у site/js/poriad.js.
     */
    fun ticket(url: String): String {
        val cut = url.indexOf('#').takeIf { it >= 0 } ?: url.length
        val base = url.take(cut)
        if (UTM.containsMatchIn(base)) return url
        val glue = if ('?' !in base) "?" else if (base.endsWith('?') || base.endsWith('&')) "" else "&"
        return "$base${glue}utm_source=poriad${url.drop(cut)}"
    }

    private val UTM = Regex("[?&]utm_source=")

    private val PATTERN =
        Regex("""(?:https://(?:www\.)?poriad\.app/e/|[a-z][a-z0-9+.-]*://event/)([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})/?(?:\?(?:[^#]*&)?by=([A-Za-z0-9_-]{22})(?=[&#]|$))?(?:[?&#].*)?""")
}
