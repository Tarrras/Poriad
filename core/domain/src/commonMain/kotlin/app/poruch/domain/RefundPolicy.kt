package app.poruch.domain

/**
 * Як повертаються гроші за онлайн-подію (`events.refund_policy`): обирає організатор у кабінеті, людина бачить до заявки.
 * Скасував організатор — повертає все за будь-якого правила (Умови, «Оплата онлайн»).
 */
enum class RefundPolicy(val key: String) {
    /** Повне повернення, якщо скасувати заявку щонайменше за 48 год до початку. */
    BEFORE_48H("before_48h"),
    BEFORE_24H("before_24h"),
    /** Лише якщо подію скасують. */
    CANCEL_ONLY("cancel_only");

    companion object {
        fun of(key: String?): RefundPolicy? = entries.firstOrNull { it.key == key }
    }
}
