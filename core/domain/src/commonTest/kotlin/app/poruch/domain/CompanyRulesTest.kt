package app.poruch.domain

import kotlin.test.*

/** Instagram у профілі для «Хочу піти з компанією»: що людина вставляє — і що з того лишається (docs/return-hooks.md). */
class CompanyRulesTest {
    @Test fun aPastedHandleOrLinkBecomesTheHandle() {
        assertEquals("taras.v", CompanyRules.normalizeInstagram(" @Taras.V "))
        assertEquals("taras_v", CompanyRules.normalizeInstagram("https://www.instagram.com/taras_v/?igsh=abc123"))
        assertEquals("taras_v", CompanyRules.normalizeInstagram("instagram.com/Taras_V"))
        assertEquals("", CompanyRules.normalizeInstagram("   "))
    }

    @Test fun onlyAHandleIsValid() {
        assertTrue(CompanyRules.isValidInstagram("taras.v_1"))
        assertTrue(CompanyRules.isValidInstagram(""), "empty clears it")
        assertFalse(CompanyRules.isValidInstagram("тарас"))
        assertFalse(CompanyRules.isValidInstagram("a b"))
        assertFalse(CompanyRules.isValidInstagram("x".repeat(31)))
        assertFalse(CompanyRules.isValidInstagram(CompanyRules.normalizeInstagram("https://t.me/taras")))
    }
}
