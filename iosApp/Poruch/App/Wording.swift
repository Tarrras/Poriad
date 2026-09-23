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
        case is AppErrorCapacityBelowAttendance: "Не можна зменшити кількість місць нижче за тих, хто вже йде"
        case is AppErrorAlreadyMember: "Ви вже берете участь у цій події"
        case is AppErrorOrganizerCannotJoin: "Ви організатор цієї події — місце гостя вам не потрібне"
        case is AppErrorEventHasSpace: "У події вже є вільні місця — приєднуйтесь одразу"
        case is AppErrorImageUploadFailed: "Не вдалося завантажити зображення"
        case is AppErrorNotMember: "Писати можуть лише організатор і підтверджені учасники"
        case is AppErrorChatClosed: "Чат закрито: подія давно минула"
        case is AppErrorTooManyMessages: "Забагато повідомлень поспіль. Зачекайте хвилину"
        case is AppErrorInvalidMessage: "Повідомлення порожнє або задовге (до 2000 символів)"
        case is AppErrorObjectionableContent: "Текст містить слова, які ми не публікуємо. Перепишіть, будь ласка."
        case is AppErrorLinkExpired: "Посилання застаріло або вже використане. Запросіть новий лист на цьому пристрої"
        case is AppErrorLinkOnAnotherDevice: "Відкрийте посилання з листа на тому самому пристрої, де ви реєструвались або запитували відновлення."
        case is AppErrorInvalidEmail: "Вкажіть коректний email"
        case is AppErrorInvalidName: "Вкажіть імʼя від 2 до 60 символів"
        case is AppErrorWeakPassword: "Пароль має містити щонайменше 8 символів"
        case is AppErrorSamePassword: "Новий пароль збігається з поточним"
        // Відхилена чернетка називає поля, тож повідомлення каже правило кожного.
        case let draft as AppErrorInvalidDraft:
            draft.fields.map(\.text).joined(separator: ". ")
        default: "Не вдалося виконати дію. Спробуйте ще раз"
        }
    }
}

extension DraftField {
    /// Правило поля одним реченням. Межі з `EventRules`, тими самими, що перевіряє `EventDraft.validate`.
    var text: String { text(length: nil) }

    /// З довжиною набраного кажемо, в який бік помилка: «щонайменше» чи «не більше».
    func text(length: Int?) -> String {
        let rules = EventRules.shared
        switch name {
        case "TITLE": return lengthRule("Назва", low: Int(rules.titleLength.first), high: Int(rules.titleLength.last), length)
        case "DESCRIPTION": return lengthRule("Опис", low: Int(rules.descriptionLength.first), high: Int(rules.descriptionLength.last), length)
        case "CATEGORY": return "Оберіть категорію"
        case "ADDRESS": return "Вкажіть місто й адресу"
        case "LOCATION": return "Позначте точку зустрічі на мапі"
        case "CAPACITY": return "Кількість місць — від \(rules.capacity.first) до \(rules.capacity.last)"
        case "STARTS_AT": return "Початок має бути в майбутньому"
        case "ENDS_AT": return "Кінець має бути пізніше за початок"
        case "TIME_ZONE": return "Не вдалося визначити часовий пояс. Оберіть місце ще раз"
        case "AGE_LIMITS": return "Вік — від \(SafetyRules.shared.MIN_SIGNUP_AGE) до \(SafetyRules.shared.MAX_AGE_LIMIT), і «від» не більше за «до»"
        case "CONTACT_URL": return "Посилання на чат має починатися з https:// і не містити пробілів"
        default: return "Фото — JPEG, PNG або WebP до 5 МБ"
        }
    }

    private func lengthRule(_ subject: String, low: Int, high: Int, _ length: Int?) -> String {
        if let length, length < low { return "\(subject) — щонайменше \(low) \(ukrainianPlural(low, "символ", "символи", "символів"))" }
        if let length, length > high { return "\(subject) — не більше \(high) \(ukrainianPlural(high, "символ", "символи", "символів")) (зараз \(length))" }
        return "\(subject) — від \(low) до \(high) символів"
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
        case "RATING_SENT": "Дякуємо за оцінку"
        case "REQUEST_SENT": "Запит надіслано організатору"
        case "REPORT_SENT": "Дякуємо. Модерація перегляне скаргу"
        case "USER_BLOCKED": "Заблоковано"
        case "AGE_CONFIRMED": "Вік підтверджено"
        default: "Збільшіть масштаб мапи, щоб побачити всі події в цій області"
        }
    }
}
