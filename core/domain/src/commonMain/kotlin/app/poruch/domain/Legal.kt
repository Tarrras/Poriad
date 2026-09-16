package app.poruch.domain

/**
 * Адреси юридичних сторінок і підтримки. Сторінки лежать у `site/`; домен — заглушка до появи
 * хостингу, тому все зібрано в одному місці, щоб замінити один раз.
 */
object LegalLinks {
    const val SITE = "https://poruch.app"
    const val TERMS = "$SITE/terms.html"
    const val PRIVACY = "$SITE/privacy.html"
    const val DELETE_ACCOUNT = "$SITE/delete-account.html"
    const val SUPPORT_EMAIL = "support@poruch.app"
}
