// Sign in with Apple: відкликання токенів при видаленні акаунта (App Store 5.1.1(v)). Свіжий
// authorization code з повторного підтвердження в застосунку міняємо на refresh token і відкликаємо
// його — Apple знімає зв'язок застосунку з Apple ID. client_secret — короткий ES256 JWT ключем
// Sign in with Apple. Лише WebCrypto, без імпортів Deno: перевірка — node apple.test.mjs поруч.

export type AppleConfig = { teamId: string; clientId: string; keyId: string; key: string };

const APPLE = "https://appleid.apple.com";

export async function revokeApple(code: string, config: AppleConfig, fetchFn: typeof fetch = fetch): Promise<void> {
  const secret = await clientSecret(config);
  const form = (fields: Record<string, string>) =>
    new URLSearchParams({ client_id: config.clientId, client_secret: secret, ...fields });
  const tokenRes = await fetchFn(`${APPLE}/auth/token`, { method: "POST", body: form({ grant_type: "authorization_code", code }) });
  const tokens = await tokenRes.json().catch(() => ({}));
  if (!tokenRes.ok || !tokens.refresh_token) throw new Error(`apple token ${tokenRes.status} ${tokens.error ?? ""}`.trim());
  const revokeRes = await fetchFn(`${APPLE}/auth/revoke`, {
    method: "POST", body: form({ token: tokens.refresh_token, token_type_hint: "refresh_token" }),
  });
  if (!revokeRes.ok) throw new Error(`apple revoke ${revokeRes.status}`);
}

/** JWT на 5 хвилин: Apple приймає до півроку, але нам потрібен лише на ці два запити. */
export async function clientSecret({ teamId, clientId, keyId, key }: AppleConfig, now = Date.now()): Promise<string> {
  // Ключ .p8 у секреті буває з буквальними `\n` замість переносів — як і APNS_KEY.
  const body = key.replace(/\\n/g, "\n").replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  const pk = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const iat = Math.floor(now / 1000);
  const part = (value: unknown) => b64url(new TextEncoder().encode(JSON.stringify(value)));
  const input = `${part({ alg: "ES256", kid: keyId })}.${part({ iss: teamId, iat, exp: iat + 300, aud: APPLE, sub: clientId })}`;
  // WebCrypto віддає підпис ECDSA сирим r‖s — саме так його хоче JWS.
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, pk, new TextEncoder().encode(input));
  return `${input}.${b64url(new Uint8Array(signature))}`;
}

function b64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
