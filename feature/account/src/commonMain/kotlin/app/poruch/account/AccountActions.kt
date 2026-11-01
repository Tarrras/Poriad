package app.poruch.account
import app.poruch.domain.*
import kotlinx.datetime.LocalDate
class AccountActions(private val repository: AuthRepository) {
    suspend fun signIn(email: String, password: String) { validate(email,password); repository.signIn(email,password) }
    /** [birthDate] — ISO-8601. Вік перевіряємо тут, щоб сказати людині до запиту; база перевірить ще раз. */
    suspend fun signUp(email: String, password: String, name: String, birthDate: String, today: LocalDate): Boolean {
        validate(email,password)
        if (!AccountRules.isName(name)) fail(AppError.InvalidName)
        val declared = runCatching { LocalDate.parse(birthDate) }.getOrElse { fail(AppError.Rejected) }
        if (!SafetyRules.isSignupAge(declared,today)) fail(AppError.Underage)
        return repository.signUp(email,password,name,declared.toString())
    }
    /** Реєстрація з галочкою «Мені вже є 18»: без галочки форма кнопку не вмикає, тож сюди вона приходить поставленою. */
    suspend fun signUp(email: String, password: String, name: String): Boolean {
        validate(email,password)
        if (!AccountRules.isName(name)) fail(AppError.InvalidName)
        return repository.signUp(email,password,name,null)
    }
    suspend fun sendCode(email: String) {
        if (!AccountRules.isEmail(email)) fail(AppError.InvalidEmail)
        repository.sendCode(email)
    }
    suspend fun verifyCode(email: String, code: String) {
        if (!AccountRules.isEmail(email)) fail(AppError.InvalidEmail)
        if (!AccountRules.isCode(code)) fail(AppError.InvalidCode)
        repository.verifyCode(email,code)
    }
    private fun validate(email: String, password: String) {
        if (!AccountRules.isEmail(email)) fail(AppError.InvalidEmail)
        if (!AccountRules.isPassword(password)) fail(AppError.WeakPassword)
    }
}
