package app.poruch.account
import app.poruch.domain.*
class AccountActions(private val repository: AuthRepository) {
    suspend fun signIn(email: String, password: String) { validate(email,password); repository.signIn(email,password) }
    suspend fun signUp(email: String, password: String, name: String): Boolean {
        validate(email,password)
        if (!AccountRules.isName(name)) fail(AppError.InvalidName)
        return repository.signUp(email,password,name)
    }
    private fun validate(email: String, password: String) {
        if (!AccountRules.isEmail(email)) fail(AppError.InvalidEmail)
        if (!AccountRules.isPassword(password)) fail(AppError.WeakPassword)
    }
}
