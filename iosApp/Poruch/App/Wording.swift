import Foundation
import Shared

/// Єдине місце, де іменований випадок стає текстом. Друга мова — зміна лише тут.
extension AppNotice {
    var text: String {
        if let failed = self as? AppNoticeFailed { return failed.error.text }
        if let told = self as? AppNoticeTold { return told.message.text }
        return ""
    }
}

extension AppError {
    var text: String {
        switch self {
        case is AppErrorNetwork: "Немає звʼязку. Перевірте інтернет і спробуйте ще раз"
        case is AppErrorNotConfigured: "Застосунок не налаштовано: бракує ключа Supabase"
        case is AppErrorServiceUnavailable: "Сервіс тимчасово недоступний. Спробуйте ще раз"
        case is AppErrorRejected: "Не вдалося виконати дію. Перевірте дані та час події"
        case is AppErrorTooManyAttempts: "Забагато спроб. Спробуйте трохи пізніше"
        case is AppErrorSessionRequired: "Увійдіть у свій обліковий запис"
        case is AppErrorInvalidCredentials: "Перевірте email і пароль. Якщо профілю ще немає — створіть його"
        case is AppErrorEmailNotConfirmed: "Підтвердьте email за посиланням у листі"
        case is AppErrorNotOwner: "Ця дія доступна лише організатору"
        case is AppErrorEventUnavailable: "Подія недоступна"
        case is AppErrorEventCancelled: "Подію скасовано"
        case is AppErrorEventFull: "Вільних місць уже немає"
        case is AppErrorAlreadyMember: "Ви вже берете участь у цій події"
        case is AppErrorOrganizerCannotJoin: "Ви організатор цієї події — місце гостя вам не потрібне"
        case is AppErrorEventHasSpace: "У події вже є вільні місця — приєднуйтесь одразу"
        case is AppErrorImageUploadFailed: "Не вдалося завантажити зображення"
        case is AppErrorNotMember: "Писати можуть лише організатор і підтверджені учасники"
        case is AppErrorChatClosed: "Чат закрито: подія давно минула"
        case is AppErrorTooManyMessages: "Забагато повідомлень поспіль. Зачекайте хвилину"
        case is AppErrorInvalidMessage: "Повідомлення порожнє або задовге (до 2000 символів)"
        case is AppErrorObjectionableContent: "Текст містить слова, які ми не публікуємо. Перепишіть, будь ласка."
        case is AppErrorLinkOnAnotherDevice: "Відкрийте посилання з листа на тому самому пристрої, де ви реєструвались або запитували відновлення."
        case is AppErrorInvalidEmail: "Вкажіть коректний email"
        case is AppErrorInvalidName: "Вкажіть імʼя від 2 до 60 символів"
        case is AppErrorWeakPassword: "Пароль має містити щонайменше 8 символів"
        // Відхилена чернетка називає поля, тож повідомлення вказує на них.
        case let draft as AppErrorInvalidDraft:
            "Перевірте поля: " + draft.fields.map(\.text).joined(separator: ", ")
        default: "Не вдалося виконати дію. Спробуйте ще раз"
        }
    }
}

extension DraftField {
    var text: String {
        switch name {
        case "TITLE": "назва (3–120 символів)"
        case "DESCRIPTION": "опис (10–5000 символів)"
        case "CATEGORY": "категорія"
        case "ADDRESS": "місто та адреса"
        case "LOCATION": "точка на мапі"
        case "CAPACITY": "кількість місць (1–10000)"
        case "STARTS_AT": "майбутня дата початку"
        case "ENDS_AT": "час закінчення"
        case "TIME_ZONE": "часовий пояс"
        case "AGE_LIMITS": "вікові обмеження"
        case "CONTACT_URL": "посилання на чат (лише https)"
        default: "фото"
        }
    }
}

extension AppMessage {
    var text: String {
        switch name {
        case "JOINED_EVENT": "Ви приєдналися до події"
        case "JOINED_WAITLIST": "Ви в черзі. Місце звільниться — додамо вас автоматично"
        case "SIGNED_IN": "Ви увійшли"
        case "ACCOUNT_CREATED": "Профіль створено"
        case "CONFIRM_EMAIL_FIRST": "Підтвердьте email за посиланням у листі, потім увійдіть"
        case "EVENT_PUBLISHED": "Подію опубліковано"
        case "CHANGES_SAVED": "Зміни збережено"
        case "PHOTO_ADDED": "Фото додано"
        case "RECOVERY_SENT": "Якщо профіль існує, лист для відновлення вже надіслано"
        case "PASSWORD_CHANGED": "Пароль змінено"
        case "SET_NEW_PASSWORD": "Вкажіть новий пароль у профілі"
        case "EMAIL_CONFIRMED": "Email підтверджено"
        case "ACCOUNT_DELETED": "Обліковий запис видалено"
        default: "Збільшіть масштаб мапи, щоб побачити всі події в цій області"
        }
    }
}
