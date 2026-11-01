// Хто має підтвердити видалення акаунта і чим. Акаунт з поштою — паролем або свіжим входом: акаунт, створений кодом з
// пошти (1.5, вхід на сайті), пароля не має, а видалити його в застосунку мусить бути можна (App Store 5.1.1(v)).
// Чиста логіка без Deno: перевірка — node reauth.test.mjs поруч.

/** Свіжий вхід — не старший за 10 хв: застосунок просить ще раз код з пошти й одразу видаляє. */
export const FRESH_SECONDS = 600;

/** Як AppState.passwordless навпаки: провайдерів нема або серед них email. Google, Apple — без пароля й без перевірки. */
export function needsReauth(providers: string[]): boolean {
  return providers.length === 0 || providers.includes("email");
}

/**
 * Чи є в access-токені вхід не старший за [FRESH_SECONDS] (claim `amr`: `{method, timestamp}` кожного входу сесії).
 * Підпис не перевіряємо: токен уже прийняв getUser, а тут лише читаємо його claims.
 */
export function freshLogin(token: string, nowSeconds: number): boolean {
  const part = token.split(".")[1];
  if (!part) return false;
  let claims: { amr?: unknown };
  try {
    const bytes = Uint8Array.from(atob(part.replace(/-/g, "+").replace(/_/g, "/")), (c) => c.charCodeAt(0));
    claims = JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    return false;
  }
  return Array.isArray(claims?.amr) && claims.amr.some((a) =>
    typeof a?.timestamp === "number" && a.timestamp >= nowSeconds - FRESH_SECONDS);
}
