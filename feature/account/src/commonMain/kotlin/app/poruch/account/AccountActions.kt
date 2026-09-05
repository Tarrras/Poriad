package app.poruch.account
import app.poruch.domain.*
class AccountActions(private val repository: AuthRepository) {
    suspend fun signIn(email: String, password: String) { validate(email,password); repository.signIn(email,password) }
    suspend fun signUp(email: String, password: String, name: String): Boolean {
        validate(email,password)
        if (name.trim().length !in 2..60) throw AppException(Failure.VALIDATION,"Вкажіть ім’я від 2 до 60 символів")
        return repository.signUp(email,password,name)
    }
    private fun validate(email: String, password: String) {
        if (!Regex("^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$").matches(email.trim())) throw AppException(Failure.VALIDATION,"Вкажіть коректний email")
        if (password.length < 8) throw AppException(Failure.VALIDATION,"Пароль має містити щонайменше 8 символів")
    }
}
