package app.poruch.domain

import kotlin.math.abs

/**
 * Заклад з `public.places`: одна точка, де стоять події афіші. Той самий ключ, що групує піни
 * в [MapPins], тож тап по місцю відкриває саме його пін. Спільнотних подій тут нема.
 */
data class Place(
    val id: String,
    val name: String,
    val city: String,
    val address: String,
    val latitude: Double,
    val longitude: Double,
    /** Скільки майбутніх подій, які бачить цей акаунт. */
    val upcoming: Int
) {
    /**
     * Те саме число, що покаже стос цього піна: події на точці в уже склеєному [index] (дублі між продавцями й прокат —
     * одна). Сервер рахує різні назви, і рядок «26 подій» відкривав «Тут подій: 24». Нема в індексі — як порахував сервер.
     */
    fun countedIn(index: List<EventIndexEntry>): Place {
        val here = index.count { isAt(it.latitude, it.longitude) }
        return if (here > 0 && here != upcoming) copy(upcoming = here) else this
    }

    /** Шість знаків після коми, як у [MapPins]: координати закладу й події збігаються за побудовою. */
    fun isAt(latitude: Double, longitude: Double) =
        abs(this.latitude - latitude) < SAME_POINT && abs(this.longitude - longitude) < SAME_POINT

    private companion object {
        const val SAME_POINT = 0.000_000_5
    }
}
