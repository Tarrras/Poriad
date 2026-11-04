package app.poruch.domain

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/** Номер з реквізитів — той самий, що розпізнає сервер (`private.has_payment_details`), групами по чотири. */
class PaymentNumberTest {
    @Test fun cardFromAnyWriting() {
        assertEquals("4111 1111 1111 1111", ChatRules.paymentNumber("Картка 4111111111111111, Олена"))
        assertEquals("4111 1111 1111 1111", ChatRules.paymentNumber("моно: 4111-1111-1111-1111"))
        assertEquals("5555 5555 5555 4444", ChatRules.paymentNumber("5555 5555 5555 4444 — 250 грн"))
    }

    @Test fun ibanBeatsCard() {
        assertEquals("UA21 3223 1300 0002 6007 2335 6600 1", ChatRules.paymentNumber("IBAN ua21 3223 1300 0002 6007 2335 6600 1, ФОП"))
    }

    @Test fun notANumberToPay() {
        assertNull(ChatRules.paymentNumber("Дзвоніть +380 67 123 45 67"), "телефон")
        assertNull(ChatRules.paymentNumber("4111 1111 1111 1112"), "не проходить Луна")
        assertNull(ChatRules.paymentNumber("0000 0000 0000 0000"), "Луна проходить, але це не картка")
        assertNull(ChatRules.paymentNumber("Оплата на банку: send.monobank.ua/jar/abc"), "посилання копіюють цілим повідомленням")
    }
}
