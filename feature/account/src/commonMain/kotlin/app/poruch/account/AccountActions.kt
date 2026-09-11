package app.poruch.account
import app.poruch.domain.*
import kotlinx.datetime.LocalDate
class AccountActions(private val repository: AuthRepository) {
    suspend fun signIn(email: String, password: String) { validate(email,password); repository.signIn(email,password) }
    /**
     * [birthDate] is ISO-8601 and checked here so the person is told before the account is
     * attempted; the database checks it again inside the transaction that would create the account.
     */
    suspend fun signUp(email: String, password: String, name: String, birthDate: String, today: LocalDate): Boolean {
        validate(email,password)
        if (!AccountRules.isName(name)) fail(AppError.InvalidName)
        val declared = runCatching { LocalDate.parse(birthDate) }.getOrElse { fail(AppError.Rejected) }
        if (!SafetyRules.isSignupAge(declared,today)) fail(AppError.Underage)
        return repository.signUp(email,password,name,declared.toString())
    }
    private fun validate(email: String, password: String) {
        if (!AccountRules.isEmail(email)) fail(AppError.InvalidEmail)
        if (!AccountRules.isPassword(password)) fail(AppError.WeakPassword)
    }
}
